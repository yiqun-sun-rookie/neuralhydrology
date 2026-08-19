"""Causal end-to-end rollout, registered losses, and training controls."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
from math import isfinite
from typing import Mapping, Sequence

import torch
from torch.nn import functional as functional

from .filter import DifferentiableInteractingMultipleModel
from .hbv import HBV15Model, forecast_global_state
from .network import HistoryTransitionNetwork, build_history_features
from .probability_audit import (
    balanced_active_row_oracle_brier,
    build_active_row_oracle,
)
from .synthetic import SyntheticBatch


@dataclass(frozen=True)
class TrainingStatistics:
    feature_mean: torch.Tensor
    feature_standard_deviation: torch.Tensor
    flow_standard_deviation: torch.Tensor
    state_standard_deviation: torch.Tensor


@dataclass(frozen=True)
class LossWeights:
    forecast: float = 1.0
    state: float = 0.2
    prior_cross_entropy: float = 0.1
    transition_kl: float = 1e-3
    transition_temporal_smoothness: float = 1e-3
    active_row_oracle_brier: float = 0.0

    def __post_init__(self) -> None:
        values = (
            self.forecast,
            self.state,
            self.prior_cross_entropy,
            self.transition_kl,
            self.transition_temporal_smoothness,
            self.active_row_oracle_brier,
        )
        if any(not isfinite(value) or value < 0.0 for value in values):
            raise ValueError("loss weights must be finite and nonnegative")
        if self.forecast <= 0.0:
            raise ValueError("forecast loss weight must be positive")


DEFAULT_LOSS_WEIGHTS = LossWeights()


@dataclass(frozen=True)
class LossBreakdown:
    forecast: torch.Tensor
    state: torch.Tensor
    prior_cross_entropy: torch.Tensor
    transition_kl: torch.Tensor
    transition_temporal_smoothness: torch.Tensor
    active_row_oracle_brier: torch.Tensor
    total: torch.Tensor


@dataclass(frozen=True)
class RolloutResult:
    losses: LossBreakdown
    transition_matrices: torch.Tensor
    transition_corrections: torch.Tensor
    prior_probabilities: torch.Tensor
    posterior_probabilities: torch.Tensor
    global_posterior_states: torch.Tensor
    forecast_discharge: torch.Tensor
    forecast_valid_mask: torch.Tensor
    forecast_leads: tuple[int, ...]


@dataclass(frozen=True)
class TrainingResult:
    best_epoch: int
    best_validation_loss: float
    history: tuple[dict[str, float], ...]
    best_network_state: Mapping[str, torch.Tensor]
    test_reads_before_selection: int


def fit_training_statistics(batch: SyntheticBatch) -> TrainingStatistics:
    """Fit every normalization constant from training blocks only."""
    days = batch.assimilation_days
    modes = functional.one_hot(
        batch.true_process_indices[:, :days], num_classes=3
    ).to(dtype=batch.forcing.dtype)
    features = torch.cat(
        (
            batch.forcing[:, :days],
            batch.truth_states[:, :days],
            modes,
        ),
        dim=-1,
    ).reshape(-1, 21)
    feature_standard_deviation = torch.clamp(
        features.std(dim=0, unbiased=False), min=1e-6
    )
    flow_standard_deviation = torch.clamp(
        batch.truth_discharge[:, :days].std(unbiased=False), min=1e-6
    )
    state_standard_deviation = torch.clamp(
        batch.truth_states[:, :days].reshape(-1, 15).std(
            dim=0, unbiased=False
        ),
        min=1e-6,
    )
    return TrainingStatistics(
        feature_mean=features.mean(dim=0),
        feature_standard_deviation=feature_standard_deviation,
        flow_standard_deviation=flow_standard_deviation,
        state_standard_deviation=state_standard_deviation,
    )


def compute_losses(
    *,
    batch: SyntheticBatch,
    statistics: TrainingStatistics,
    transition_matrices: torch.Tensor,
    prior_probabilities: torch.Tensor,
    global_posterior_states: torch.Tensor,
    forecast_discharge: torch.Tensor,
    forecast_leads: Sequence[int],
    base_transition: torch.Tensor,
    loss_weights: LossWeights = DEFAULT_LOSS_WEIGHTS,
    oracle_duration_bounds: tuple[int, int] | None = None,
) -> tuple[LossBreakdown, torch.Tensor]:
    """Compute the frozen five-term objective and no-switch forecast mask."""
    leads = tuple(int(value) for value in forecast_leads)
    days = batch.assimilation_days
    forecast_errors = []
    valid_masks = []
    origin_modes = batch.true_process_indices[:, :days]
    for lead_index, lead in enumerate(leads):
        target = batch.truth_discharge[:, lead : lead + days]
        target_modes = batch.true_process_indices[:, lead : lead + days]
        valid = origin_modes == target_modes
        error = (
            (forecast_discharge[:, :, lead_index] - target)
            / statistics.flow_standard_deviation
        ).square()
        forecast_errors.append(error)
        valid_masks.append(valid)
    error_tensor = torch.stack(forecast_errors, dim=-1)
    valid_mask = torch.stack(valid_masks, dim=-1)
    forecast = error_tensor[valid_mask].mean()

    standardized_state_error = (
        (
            global_posterior_states - batch.truth_states[:, :days]
        )
        / statistics.state_standard_deviation
    ).square()
    state = standardized_state_error.mean()
    true_modes = batch.true_process_indices[:, :days]
    prior_cross_entropy = functional.nll_loss(
        torch.log(torch.clamp(prior_probabilities, min=torch.finfo(prior_probabilities.dtype).tiny)).reshape(-1, 3),
        true_modes.reshape(-1),
    )
    base = base_transition.reshape(1, 1, 3, 3)
    transition_kl = torch.sum(
        transition_matrices
        * (torch.log(transition_matrices) - torch.log(base)),
        dim=-1,
    ).mean()
    if transition_matrices.shape[1] > 1:
        transition_temporal_smoothness = (
            transition_matrices[:, 1:] - transition_matrices[:, :-1]
        ).square().mean()
    else:
        transition_temporal_smoothness = torch.zeros(
            (), dtype=transition_matrices.dtype, device=transition_matrices.device
        )
    if oracle_duration_bounds is None:
        if loss_weights.active_row_oracle_brier > 0.0:
            raise ValueError(
                "oracle_duration_bounds are required when active-row oracle loss is positive"
            )
        active_row_oracle_brier = torch.zeros(
            (), dtype=transition_matrices.dtype, device=transition_matrices.device
        )
    else:
        minimum_duration, maximum_duration = (
            int(value) for value in oracle_duration_bounds
        )
        oracle = build_active_row_oracle(
            batch, minimum_duration, maximum_duration
        )
        active_row_oracle_brier = balanced_active_row_oracle_brier(
            transition_matrices, oracle, minimum_duration
        )
    total = (
        loss_weights.forecast * forecast
        + loss_weights.state * state
        + loss_weights.prior_cross_entropy * prior_cross_entropy
        + loss_weights.transition_kl * transition_kl
        + loss_weights.transition_temporal_smoothness
        * transition_temporal_smoothness
        + loss_weights.active_row_oracle_brier * active_row_oracle_brier
    )
    return (
        LossBreakdown(
            forecast=forecast,
            state=state,
            prior_cross_entropy=prior_cross_entropy,
            transition_kl=transition_kl,
            transition_temporal_smoothness=transition_temporal_smoothness,
            active_row_oracle_brier=active_row_oracle_brier,
            total=total,
        ),
        valid_mask,
    )


def rollout_end_to_end(
    batch: SyntheticBatch,
    network: HistoryTransitionNetwork,
    estimator: DifferentiableInteractingMultipleModel,
    forecast_model: HBV15Model,
    statistics: TrainingStatistics,
    *,
    forecast_leads: Sequence[int] = (1, 3, 7),
    observations: torch.Tensor | None = None,
    loss_weights: LossWeights = DEFAULT_LOSS_WEIGHTS,
    oracle_duration_bounds: tuple[int, int] | None = None,
) -> RolloutResult:
    """Run the complete causal history-network to future-flow computation."""
    leads = tuple(int(value) for value in forecast_leads)
    if not leads or min(leads) <= 0 or max(leads) >= batch.forcing.shape[1]:
        raise ValueError("forecast_leads must be positive and covered by forcing")
    batch_size = batch.forcing.shape[0]
    days = batch.assimilation_days
    observed = batch.observations if observations is None else observations
    if observed.shape != batch.observations.shape:
        raise ValueError("observations override must preserve the batch shape")

    states = batch.initial_states.unsqueeze(1).expand(-1, 3, -1).clone()
    covariances = (
        batch.initial_covariances.unsqueeze(1).expand(-1, 3, -1, -1).clone()
    )
    probabilities = torch.full(
        (batch_size, 3),
        1.0 / 3.0,
        dtype=batch.forcing.dtype,
        device=batch.forcing.device,
    )
    hidden = network.initial_hidden(
        batch_size,
        dtype=batch.forcing.dtype,
        device=batch.forcing.device,
    )
    previous_forcing = torch.zeros(
        (batch_size, 3), dtype=batch.forcing.dtype, device=batch.forcing.device
    )
    previous_global_state = batch.initial_states

    transitions = []
    corrections = []
    prior_probabilities = []
    posterior_probabilities = []
    global_states = []
    forecasts = []
    for day in range(days):
        previous_features = build_history_features(
            previous_forcing,
            previous_global_state,
            probabilities,
        )
        transition, hidden, correction = network(previous_features, hidden)
        update = estimator.step(
            states=states,
            covariances=covariances,
            probabilities=probabilities,
            transition_matrix=transition,
            forcing=batch.forcing[:, day],
            observation=observed[:, day],
        )
        future_forcing = batch.forcing[
            :, day + 1 : day + 1 + max(leads)
        ]
        forecast_by_lead = forecast_global_state(
            update.global_posterior_states,
            future_forcing,
            forecast_model,
            leads,
        )
        forecasts.append(
            torch.stack([forecast_by_lead[lead] for lead in leads], dim=-1)
        )
        transitions.append(transition)
        corrections.append(correction)
        prior_probabilities.append(update.prior_probabilities)
        posterior_probabilities.append(update.posterior_probabilities)
        global_states.append(update.global_posterior_states)

        states = update.posterior_states
        covariances = update.posterior_covariances
        probabilities = update.posterior_probabilities
        previous_forcing = batch.forcing[:, day]
        previous_global_state = update.global_posterior_states

    transition_tensor = torch.stack(transitions, dim=1)
    prior_tensor = torch.stack(prior_probabilities, dim=1)
    global_state_tensor = torch.stack(global_states, dim=1)
    forecast_tensor = torch.stack(forecasts, dim=1)
    losses, valid_mask = compute_losses(
        batch=batch,
        statistics=statistics,
        transition_matrices=transition_tensor,
        prior_probabilities=prior_tensor,
        global_posterior_states=global_state_tensor,
        forecast_discharge=forecast_tensor,
        forecast_leads=leads,
        base_transition=network.base_transition,
        loss_weights=loss_weights,
        oracle_duration_bounds=oracle_duration_bounds,
    )
    return RolloutResult(
        losses=losses,
        transition_matrices=transition_tensor,
        transition_corrections=torch.stack(corrections, dim=1),
        prior_probabilities=prior_tensor,
        posterior_probabilities=torch.stack(posterior_probabilities, dim=1),
        global_posterior_states=global_state_tensor,
        forecast_discharge=forecast_tensor,
        forecast_valid_mask=valid_mask,
        forecast_leads=leads,
    )


def _slice_batch(batch: SyntheticBatch, indices: Sequence[int]) -> SyntheticBatch:
    selected = torch.as_tensor(tuple(indices), dtype=torch.int64)
    index_values = tuple(int(value) for value in indices)
    return SyntheticBatch(
        forcing=batch.forcing[selected],
        observations=batch.observations[selected],
        truth_states=batch.truth_states[selected],
        truth_discharge=batch.truth_discharge[selected],
        true_process_indices=batch.true_process_indices[selected],
        projection_adjustments=batch.projection_adjustments[selected],
        initial_states=batch.initial_states[selected],
        initial_covariances=batch.initial_covariances[selected],
        switch_days=batch.switch_days[selected],
        block_ids=tuple(batch.block_ids[index] for index in index_values),
        block_seeds=tuple(batch.block_seeds[index] for index in index_values),
        accepted_process_seeds=tuple(
            batch.accepted_process_seeds[index] for index in index_values
        ),
        rejected_process_seeds=batch.rejected_process_seeds,
        assimilation_days=batch.assimilation_days,
    )


def _loss_values(losses: LossBreakdown) -> dict[str, float]:
    return {
        "total": float(losses.total.detach()),
        "forecast": float(losses.forecast.detach()),
        "state": float(losses.state.detach()),
        "prior_cross_entropy": float(losses.prior_cross_entropy.detach()),
        "transition_kl": float(losses.transition_kl.detach()),
        "transition_temporal_smoothness": float(
            losses.transition_temporal_smoothness.detach()
        ),
        "active_row_oracle_brier": float(
            losses.active_row_oracle_brier.detach()
        ),
    }


def train_one_epoch(
    batch: SyntheticBatch,
    network: HistoryTransitionNetwork,
    estimator: DifferentiableInteractingMultipleModel,
    forecast_model: HBV15Model,
    statistics: TrainingStatistics,
    optimizer: torch.optim.Optimizer,
    *,
    forecast_leads: Sequence[int] = (1, 3, 7),
    batch_size: int = 2,
    loss_weights: LossWeights = DEFAULT_LOSS_WEIGHTS,
    oracle_duration_bounds: tuple[int, int] | None = None,
) -> dict[str, float]:
    network.train()
    if batch_size <= 0:
        raise ValueError("batch_size must be positive")
    totals: dict[str, float] = {}
    maximum_forecast_gradient = 0.0
    block_count = len(batch.block_ids)
    for start in range(0, block_count, int(batch_size)):
        stop = min(start + int(batch_size), block_count)
        subset = _slice_batch(batch, range(start, stop))
        optimizer.zero_grad(set_to_none=True)
        result = rollout_end_to_end(
            subset,
            network,
            estimator,
            forecast_model,
            statistics,
            forecast_leads=forecast_leads,
            loss_weights=loss_weights,
            oracle_duration_bounds=oracle_duration_bounds,
        )
        forecast_gradients = torch.autograd.grad(
            result.losses.forecast,
            tuple(network.parameters()),
            retain_graph=True,
            allow_unused=True,
        )
        finite_forecast_gradients = [
            gradient.detach().abs().max()
            for gradient in forecast_gradients
            if gradient is not None and torch.isfinite(gradient).all()
        ]
        if finite_forecast_gradients:
            maximum_forecast_gradient = max(
                maximum_forecast_gradient,
                max(float(value) for value in finite_forecast_gradients),
            )
        result.losses.total.backward()
        torch.nn.utils.clip_grad_norm_(network.parameters(), max_norm=1.0)
        optimizer.step()
        values = _loss_values(result.losses)
        weight = stop - start
        for name, value in values.items():
            totals[name] = totals.get(name, 0.0) + weight * value
    averaged = {name: value / block_count for name, value in totals.items()}
    averaged["forecast_gradient_maximum"] = maximum_forecast_gradient
    return averaged


def evaluate_checkpoint(
    batch: SyntheticBatch,
    network: HistoryTransitionNetwork,
    estimator: DifferentiableInteractingMultipleModel,
    forecast_model: HBV15Model,
    statistics: TrainingStatistics,
    *,
    forecast_leads: Sequence[int] = (1, 3, 7),
    loss_weights: LossWeights = DEFAULT_LOSS_WEIGHTS,
    oracle_duration_bounds: tuple[int, int] | None = None,
) -> dict[str, float]:
    network.eval()
    with torch.no_grad():
        result = rollout_end_to_end(
            batch,
            network,
            estimator,
            forecast_model,
            statistics,
            forecast_leads=forecast_leads,
            loss_weights=loss_weights,
            oracle_duration_bounds=oracle_duration_bounds,
        )
    return _loss_values(result.losses)


def train_history_transition(
    training_batch: SyntheticBatch,
    validation_batch: SyntheticBatch,
    network: HistoryTransitionNetwork,
    estimator: DifferentiableInteractingMultipleModel,
    forecast_model: HBV15Model,
    statistics: TrainingStatistics,
    *,
    forecast_leads: Sequence[int] = (1, 3, 7),
    epochs: int = 2,
    batch_size: int = 2,
    learning_rate: float = 3e-4,
    weight_decay: float = 1e-4,
    forbidden_test_batch: SyntheticBatch | None = None,
    loss_weights: LossWeights = DEFAULT_LOSS_WEIGHTS,
    oracle_duration_bounds: tuple[int, int] | None = None,
) -> TrainingResult:
    """Select the checkpoint from validation loss without reading test data."""
    if epochs <= 0:
        raise ValueError("epochs must be positive")
    optimizer = torch.optim.AdamW(
        network.parameters(),
        lr=float(learning_rate),
        weight_decay=float(weight_decay),
    )
    history = []
    best_epoch = 0
    best_validation_loss = float("inf")
    best_network_state = deepcopy(network.state_dict())
    for epoch in range(1, int(epochs) + 1):
        training_values = train_one_epoch(
            training_batch,
            network,
            estimator,
            forecast_model,
            statistics,
            optimizer,
            forecast_leads=forecast_leads,
            batch_size=batch_size,
            loss_weights=loss_weights,
            oracle_duration_bounds=oracle_duration_bounds,
        )
        validation_values = evaluate_checkpoint(
            validation_batch,
            network,
            estimator,
            forecast_model,
            statistics,
            forecast_leads=forecast_leads,
            loss_weights=loss_weights,
            oracle_duration_bounds=oracle_duration_bounds,
        )
        row = {"epoch": float(epoch)}
        row.update({f"train_{name}": value for name, value in training_values.items()})
        row.update(
            {f"validation_{name}": value for name, value in validation_values.items()}
        )
        history.append(row)
        if validation_values["total"] < best_validation_loss:
            best_epoch = epoch
            best_validation_loss = validation_values["total"]
            best_network_state = deepcopy(network.state_dict())
    network.load_state_dict(best_network_state)
    return TrainingResult(
        best_epoch=best_epoch,
        best_validation_loss=best_validation_loss,
        history=tuple(history),
        best_network_state=best_network_state,
        test_reads_before_selection=0,
    )
