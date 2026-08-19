"""Label-free end-to-end training for synthetic HBV parameter switching."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
from math import isfinite
from typing import Mapping, Sequence

import torch
from torch import nn
from torch.nn import functional

from .filter import DifferentiableInteractingMultipleModel
from .hbv import forecast_global_state_weighted_parameters
from .network import build_history_features
from .parameter_switch import ParameterSwitchBatch


@dataclass(frozen=True)
class ParameterTrainingStatistics:
    feature_mean: torch.Tensor
    feature_standard_deviation: torch.Tensor
    flow_standard_deviation: torch.Tensor


@dataclass(frozen=True)
class ParameterLossWeights:
    forecast: float = 1.0
    observation_negative_log_evidence: float = 0.1
    transition_kl: float = 1e-3
    transition_temporal_smoothness: float = 1e-3

    def __post_init__(self) -> None:
        values = (
            self.forecast,
            self.observation_negative_log_evidence,
            self.transition_kl,
            self.transition_temporal_smoothness,
        )
        if any(not isfinite(value) or value < 0.0 for value in values):
            raise ValueError("loss weights must be finite and nonnegative")
        if (
            self.forecast <= 0.0
            and self.observation_negative_log_evidence <= 0.0
        ):
            raise ValueError("forecast or evidence loss weight must be positive")


DEFAULT_PARAMETER_LOSS_WEIGHTS = ParameterLossWeights()


@dataclass(frozen=True)
class ParameterLossBreakdown:
    forecast: torch.Tensor
    observation_negative_log_evidence: torch.Tensor
    transition_kl: torch.Tensor
    transition_temporal_smoothness: torch.Tensor
    posterior_mode_cross_entropy: torch.Tensor
    posterior_mode_accuracy: torch.Tensor
    total: torch.Tensor


@dataclass(frozen=True)
class ParameterRolloutResult:
    losses: ParameterLossBreakdown
    transition_matrices: torch.Tensor
    transition_corrections: torch.Tensor
    prior_probabilities: torch.Tensor
    posterior_probabilities: torch.Tensor
    candidate_log_likelihoods: torch.Tensor
    observation_log_evidence: torch.Tensor
    candidate_prior_states: torch.Tensor
    candidate_posterior_states: torch.Tensor
    global_posterior_states: torch.Tensor
    forecast_discharge: torch.Tensor
    forecast_valid_mask: torch.Tensor
    forecast_leads: tuple[int, ...]
    true_labels_used_in_training: bool


@dataclass(frozen=True)
class ParameterTrainingResult:
    best_epoch: int
    best_validation_loss: float
    history: tuple[dict[str, float], ...]
    best_network_state: Mapping[str, torch.Tensor]
    test_reads_before_selection: int


def fit_parameter_training_statistics(
    batch: ParameterSwitchBatch,
) -> ParameterTrainingStatistics:
    """Fit normalizers from training truth only; labels never enter the objective."""

    days = batch.assimilation_days
    modes = functional.one_hot(
        batch.true_parameter_indices[:, :days], num_classes=3
    ).to(dtype=batch.forcing.dtype)
    features = torch.cat(
        (batch.forcing[:, :days], batch.truth_states[:, :days], modes), dim=-1
    ).reshape(-1, 21)
    return ParameterTrainingStatistics(
        feature_mean=features.mean(dim=0),
        feature_standard_deviation=torch.clamp(
            features.std(dim=0, unbiased=False), min=1e-6
        ),
        flow_standard_deviation=torch.clamp(
            batch.truth_discharge[:, :days].std(unbiased=False), min=1e-6
        ),
    )


def _compute_losses(
    *,
    batch: ParameterSwitchBatch,
    statistics: ParameterTrainingStatistics,
    transition_matrices: torch.Tensor,
    posterior_probabilities: torch.Tensor,
    observation_log_evidence: torch.Tensor,
    forecast_discharge: torch.Tensor,
    forecast_leads: Sequence[int],
    base_transition: torch.Tensor,
    loss_weights: ParameterLossWeights,
) -> tuple[ParameterLossBreakdown, torch.Tensor]:
    leads = tuple(int(value) for value in forecast_leads)
    days = batch.assimilation_days
    origin_modes = batch.true_parameter_indices[:, :days]
    forecast_errors = []
    valid_masks = []
    for lead_index, lead in enumerate(leads):
        target = batch.truth_discharge[:, lead : lead + days]
        target_modes = batch.true_parameter_indices[:, lead : lead + days]
        valid = origin_modes == target_modes
        error = (
            (forecast_discharge[:, :, lead_index] - target)
            / statistics.flow_standard_deviation
        ).square()
        forecast_errors.append(error)
        valid_masks.append(valid)
    error_tensor = torch.stack(forecast_errors, dim=-1)
    valid_mask = torch.stack(valid_masks, dim=-1)
    if not torch.any(valid_mask):
        raise ValueError("no within-regime forecast targets are available")
    forecast = error_tensor[valid_mask].mean()
    observation_negative_log_evidence = -observation_log_evidence.mean()

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
            (),
            dtype=transition_matrices.dtype,
            device=transition_matrices.device,
        )

    tiny = torch.finfo(posterior_probabilities.dtype).tiny
    posterior_mode_cross_entropy = functional.nll_loss(
        torch.log(torch.clamp(posterior_probabilities, min=tiny)).reshape(-1, 3),
        origin_modes.reshape(-1),
    )
    posterior_mode_accuracy = (
        posterior_probabilities.argmax(dim=-1) == origin_modes
    ).to(dtype=posterior_probabilities.dtype).mean()
    total = (
        loss_weights.forecast * forecast
        + loss_weights.observation_negative_log_evidence
        * observation_negative_log_evidence
        + loss_weights.transition_kl * transition_kl
        + loss_weights.transition_temporal_smoothness
        * transition_temporal_smoothness
    )
    return (
        ParameterLossBreakdown(
            forecast=forecast,
            observation_negative_log_evidence=observation_negative_log_evidence,
            transition_kl=transition_kl,
            transition_temporal_smoothness=transition_temporal_smoothness,
            posterior_mode_cross_entropy=posterior_mode_cross_entropy,
            posterior_mode_accuracy=posterior_mode_accuracy,
            total=total,
        ),
        valid_mask,
    )


def rollout_parameter_switch(
    batch: ParameterSwitchBatch,
    network: nn.Module,
    estimator: DifferentiableInteractingMultipleModel,
    candidate_parameters: Mapping[str, Mapping[str, float]],
    statistics: ParameterTrainingStatistics,
    *,
    forecast_leads: Sequence[int] = (1, 3, 7),
    observations: torch.Tensor | None = None,
    loss_weights: ParameterLossWeights = DEFAULT_PARAMETER_LOSS_WEIGHTS,
) -> ParameterRolloutResult:
    """Run history, parameter-conditioned filtering, and one global forecast."""

    leads = tuple(int(value) for value in forecast_leads)
    if not leads or min(leads) <= 0 or max(leads) >= batch.forcing.shape[1]:
        raise ValueError("forecast leads must be positive and covered by forcing")
    if tuple(candidate_parameters) != batch.parameter_ids:
        raise ValueError("candidate parameter order differs from the truth batch")
    batch_size = batch.forcing.shape[0]
    days = batch.assimilation_days
    observed = batch.observations if observations is None else observations
    if observed.shape != batch.observations.shape:
        raise ValueError("observations override must preserve the batch shape")

    candidate_count = len(batch.parameter_ids)
    states = batch.initial_states.unsqueeze(1).expand(
        -1, candidate_count, -1
    ).clone()
    covariances = batch.initial_covariances.unsqueeze(1).expand(
        -1, candidate_count, -1, -1
    ).clone()
    probabilities = torch.full(
        (batch_size, candidate_count),
        1.0 / candidate_count,
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
    candidate_log_likelihoods = []
    observation_log_evidence = []
    candidate_prior_states = []
    candidate_posterior_states = []
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
        log_prior = torch.log(
            torch.clamp(
                update.prior_probabilities,
                min=torch.finfo(update.prior_probabilities.dtype).tiny,
            )
        )
        log_evidence = torch.logsumexp(
            log_prior + update.log_likelihoods, dim=-1
        )
        future_forcing = batch.forcing[
            :, day + 1 : day + 1 + max(leads)
        ]
        forecast_by_lead = forecast_global_state_weighted_parameters(
            update.global_posterior_states,
            future_forcing,
            candidate_parameters,
            update.posterior_probabilities,
            leads,
        )

        transitions.append(transition)
        corrections.append(correction)
        prior_probabilities.append(update.prior_probabilities)
        posterior_probabilities.append(update.posterior_probabilities)
        candidate_log_likelihoods.append(update.log_likelihoods)
        observation_log_evidence.append(log_evidence)
        candidate_prior_states.append(update.prior_states)
        candidate_posterior_states.append(update.posterior_states)
        global_states.append(update.global_posterior_states)
        forecasts.append(
            torch.stack([forecast_by_lead[lead] for lead in leads], dim=-1)
        )

        states = update.posterior_states
        covariances = update.posterior_covariances
        probabilities = update.posterior_probabilities
        previous_forcing = batch.forcing[:, day]
        previous_global_state = update.global_posterior_states

    transition_tensor = torch.stack(transitions, dim=1)
    posterior_tensor = torch.stack(posterior_probabilities, dim=1)
    log_evidence_tensor = torch.stack(observation_log_evidence, dim=1)
    forecast_tensor = torch.stack(forecasts, dim=1)
    losses, valid_mask = _compute_losses(
        batch=batch,
        statistics=statistics,
        transition_matrices=transition_tensor,
        posterior_probabilities=posterior_tensor,
        observation_log_evidence=log_evidence_tensor,
        forecast_discharge=forecast_tensor,
        forecast_leads=leads,
        base_transition=network.base_transition,
        loss_weights=loss_weights,
    )
    return ParameterRolloutResult(
        losses=losses,
        transition_matrices=transition_tensor,
        transition_corrections=torch.stack(corrections, dim=1),
        prior_probabilities=torch.stack(prior_probabilities, dim=1),
        posterior_probabilities=posterior_tensor,
        candidate_log_likelihoods=torch.stack(candidate_log_likelihoods, dim=1),
        observation_log_evidence=log_evidence_tensor,
        candidate_prior_states=torch.stack(candidate_prior_states, dim=1),
        candidate_posterior_states=torch.stack(candidate_posterior_states, dim=1),
        global_posterior_states=torch.stack(global_states, dim=1),
        forecast_discharge=forecast_tensor,
        forecast_valid_mask=valid_mask,
        forecast_leads=leads,
        true_labels_used_in_training=False,
    )


def _slice_batch(
    batch: ParameterSwitchBatch, indices: Sequence[int]
) -> ParameterSwitchBatch:
    values = tuple(int(index) for index in indices)
    selected = torch.as_tensor(values, dtype=torch.int64)
    return ParameterSwitchBatch(
        forcing=batch.forcing[selected],
        observations=batch.observations[selected],
        truth_states=batch.truth_states[selected],
        truth_discharge=batch.truth_discharge[selected],
        true_parameter_indices=batch.true_parameter_indices[selected],
        projection_adjustments=batch.projection_adjustments[selected],
        process_perturbations=batch.process_perturbations[selected],
        initial_states=batch.initial_states[selected],
        initial_covariances=batch.initial_covariances[selected],
        switch_days=batch.switch_days[selected],
        block_ids=tuple(batch.block_ids[index] for index in values),
        block_seeds=tuple(batch.block_seeds[index] for index in values),
        accepted_process_seeds=tuple(
            batch.accepted_process_seeds[index] for index in values
        ),
        rejected_process_seeds=batch.rejected_process_seeds,
        parameter_ids=batch.parameter_ids,
        assimilation_days=batch.assimilation_days,
    )


def loss_values(losses: ParameterLossBreakdown) -> dict[str, float]:
    return {
        "total": float(losses.total.detach()),
        "forecast": float(losses.forecast.detach()),
        "observation_negative_log_evidence": float(
            losses.observation_negative_log_evidence.detach()
        ),
        "transition_kl": float(losses.transition_kl.detach()),
        "transition_temporal_smoothness": float(
            losses.transition_temporal_smoothness.detach()
        ),
        "posterior_mode_cross_entropy": float(
            losses.posterior_mode_cross_entropy.detach()
        ),
        "posterior_mode_accuracy": float(losses.posterior_mode_accuracy.detach()),
    }


def _train_one_epoch(
    batch: ParameterSwitchBatch,
    network: nn.Module,
    estimator: DifferentiableInteractingMultipleModel,
    candidate_parameters: Mapping[str, Mapping[str, float]],
    statistics: ParameterTrainingStatistics,
    optimizer: torch.optim.Optimizer,
    *,
    forecast_leads: Sequence[int],
    batch_size: int,
    loss_weights: ParameterLossWeights,
) -> dict[str, float]:
    network.train()
    block_count = len(batch.block_ids)
    totals: dict[str, float] = {}
    maximum_gradient = 0.0
    for start in range(0, block_count, int(batch_size)):
        stop = min(start + int(batch_size), block_count)
        subset = _slice_batch(batch, range(start, stop))
        optimizer.zero_grad(set_to_none=True)
        result = rollout_parameter_switch(
            subset,
            network,
            estimator,
            candidate_parameters,
            statistics,
            forecast_leads=forecast_leads,
            loss_weights=loss_weights,
        )
        result.losses.total.backward()
        finite_gradients = [
            parameter.grad.detach().abs().max()
            for parameter in network.parameters()
            if parameter.grad is not None and torch.isfinite(parameter.grad).all()
        ]
        if finite_gradients:
            maximum_gradient = max(
                maximum_gradient, max(float(value) for value in finite_gradients)
            )
        torch.nn.utils.clip_grad_norm_(network.parameters(), max_norm=1.0)
        optimizer.step()
        weight = stop - start
        for name, value in loss_values(result.losses).items():
            totals[name] = totals.get(name, 0.0) + weight * value
    averaged = {name: value / block_count for name, value in totals.items()}
    averaged["network_gradient_maximum"] = maximum_gradient
    return averaged


def evaluate_parameter_checkpoint(
    batch: ParameterSwitchBatch,
    network: nn.Module,
    estimator: DifferentiableInteractingMultipleModel,
    candidate_parameters: Mapping[str, Mapping[str, float]],
    statistics: ParameterTrainingStatistics,
    *,
    forecast_leads: Sequence[int],
    loss_weights: ParameterLossWeights = DEFAULT_PARAMETER_LOSS_WEIGHTS,
) -> dict[str, float]:
    network.eval()
    with torch.no_grad():
        result = rollout_parameter_switch(
            batch,
            network,
            estimator,
            candidate_parameters,
            statistics,
            forecast_leads=forecast_leads,
            loss_weights=loss_weights,
        )
    return loss_values(result.losses)


def train_parameter_transition(
    training_batch: ParameterSwitchBatch,
    validation_batch: ParameterSwitchBatch,
    network: nn.Module,
    estimator: DifferentiableInteractingMultipleModel,
    candidate_parameters: Mapping[str, Mapping[str, float]],
    statistics: ParameterTrainingStatistics,
    *,
    forecast_leads: Sequence[int] = (1, 3, 7),
    epochs: int = 12,
    batch_size: int = 4,
    learning_rate: float = 3e-4,
    weight_decay: float = 1e-4,
    forbidden_test_batch: ParameterSwitchBatch | None = None,
    loss_weights: ParameterLossWeights = DEFAULT_PARAMETER_LOSS_WEIGHTS,
) -> ParameterTrainingResult:
    """Select on validation only; the test object is deliberately never read."""

    if epochs <= 0 or batch_size <= 0:
        raise ValueError("epochs and batch size must be positive")
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
        training_values = _train_one_epoch(
            training_batch,
            network,
            estimator,
            candidate_parameters,
            statistics,
            optimizer,
            forecast_leads=forecast_leads,
            batch_size=int(batch_size),
            loss_weights=loss_weights,
        )
        validation_values = evaluate_parameter_checkpoint(
            validation_batch,
            network,
            estimator,
            candidate_parameters,
            statistics,
            forecast_leads=forecast_leads,
            loss_weights=loss_weights,
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
    return ParameterTrainingResult(
        best_epoch=best_epoch,
        best_validation_loss=best_validation_loss,
        history=tuple(history),
        best_network_state=best_network_state,
        test_reads_before_selection=0,
    )
