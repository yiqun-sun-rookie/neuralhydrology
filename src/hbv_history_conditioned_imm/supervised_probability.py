"""Supervised active-row probability learning for the H17 capability ceiling."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
import math
import time
from typing import Any, Callable, Mapping

import torch

from .causal_duration import CausalSemiMarkovTransitionModule, ModeDurationState
from .filter import DifferentiableInteractingMultipleModel
from .long_history import ObservableAssimilationBatch
from .network import (
    FEATURE_COUNT,
    HistoryTransitionNetwork,
    StaticTransitionNetwork,
    build_history_features,
)


@dataclass(frozen=True)
class ActiveRowSupervision:
    """The only synthetic labels authorized for H17 training and scoring."""

    source_indices: torch.Tensor
    target_probabilities: torch.Tensor
    evaluation_mask: torch.Tensor
    switch_event_mask: torch.Tensor
    regime_age_before_transition: torch.Tensor

    def __post_init__(self) -> None:
        if self.source_indices.ndim != 2:
            raise ValueError("source indices must have shape [block, day]")
        shape = self.source_indices.shape
        if self.target_probabilities.shape != (*shape, 3):
            raise ValueError("target probabilities must have shape [block, day, 3]")
        if (
            self.evaluation_mask.shape != shape
            or self.switch_event_mask.shape != shape
            or self.regime_age_before_transition.shape != shape
        ):
            raise ValueError("all supervision masks and ages must share one shape")
        if self.evaluation_mask.dtype != torch.bool or self.switch_event_mask.dtype != torch.bool:
            raise ValueError("supervision masks must be boolean")
        if self.source_indices.dtype != torch.int64:
            raise ValueError("source indices must be int64")
        if self.regime_age_before_transition.dtype != torch.int64:
            raise ValueError("regime ages must be int64")
        if shape[1] <= 0 or torch.any(self.evaluation_mask[:, 0]):
            raise ValueError("day zero must not be an evaluated transition")
        if torch.any(self.switch_event_mask & ~self.evaluation_mask):
            raise ValueError("switch events must be a subset of evaluated transitions")
        evaluated_sources = self.source_indices[self.evaluation_mask]
        if (
            evaluated_sources.numel() == 0
            or torch.any(evaluated_sources < 0)
            or torch.any(evaluated_sources > 2)
        ):
            raise ValueError("evaluated source indices must lie from zero through two")
        evaluated_targets = self.target_probabilities[self.evaluation_mask]
        if (
            not torch.isfinite(evaluated_targets).all()
            or torch.any(evaluated_targets < 0.0)
            or torch.max(torch.abs(evaluated_targets.sum(dim=-1) - 1.0)) > 1e-12
        ):
            raise ValueError("evaluated target probabilities must be row stochastic")
        evaluated_ages = self.regime_age_before_transition[self.evaluation_mask]
        if torch.any(evaluated_ages <= 0):
            raise ValueError("evaluated transitions require positive prior-regime ages")


@dataclass(frozen=True)
class ProbabilityScores:
    evaluated_transition_count: int
    switch_event_count: int
    oracle_brier: float
    oracle_cross_entropy: float
    switch_hazard_mean_absolute_error: float
    mean_predicted_switch_hazard: float
    mean_oracle_switch_hazard: float
    maximum_transition_row_sum_error: float
    minimum_transition_probability: float
    age_bin_metrics: Mapping[str, Mapping[str, int | float | None]]

    def to_dict(self) -> dict[str, Any]:
        return {
            "evaluated_transition_count": self.evaluated_transition_count,
            "switch_event_count": self.switch_event_count,
            "oracle_brier": self.oracle_brier,
            "oracle_cross_entropy": self.oracle_cross_entropy,
            "switch_hazard_mean_absolute_error": self.switch_hazard_mean_absolute_error,
            "mean_predicted_switch_hazard": self.mean_predicted_switch_hazard,
            "mean_oracle_switch_hazard": self.mean_oracle_switch_hazard,
            "maximum_transition_row_sum_error": self.maximum_transition_row_sum_error,
            "minimum_transition_probability": self.minimum_transition_probability,
            "age_bin_metrics": {
                name: dict(values) for name, values in self.age_bin_metrics.items()
            },
        }


@dataclass(frozen=True)
class ObservableFeatureStatistics:
    """Normalization fitted only from a fixed-filter observable rollout."""

    feature_mean: torch.Tensor
    feature_standard_deviation: torch.Tensor
    source: str = "fixed_transition_training_observation_rollout"
    truth_used: bool = False
    supervision_used: bool = False
    validation_used: bool = False
    test_used: bool = False


@dataclass(frozen=True)
class ProbabilityRolloutResult:
    """Direct supervised probability loss and its detached diagnostics."""

    loss: torch.Tensor
    transition_matrices: torch.Tensor
    scores: ProbabilityScores
    physical_filter_gradient_stopped: bool
    duration_source_hazards: torch.Tensor | None = None
    duration_expected_ages: torch.Tensor | None = None
    posterior_mode_probabilities: torch.Tensor | None = None
    age_hazards: torch.Tensor | None = None


@dataclass(frozen=True)
class ProbabilityTrainingResult:
    """Validation-selected checkpoint without any test-set access."""

    best_epoch: int
    best_validation_brier: float
    history: tuple[Mapping[str, float], ...]
    best_network_state: Mapping[str, torch.Tensor]
    test_reads_before_selection: int


@dataclass(frozen=True)
class ProbabilityTrainingProgress:
    """Serializable full-batch optimizer state at an epoch boundary."""

    completed_epochs: int
    total_epochs: int
    best_epoch: int
    best_validation_brier: float
    history: tuple[Mapping[str, float], ...]
    best_network_state: Mapping[str, torch.Tensor]
    network_state: Mapping[str, torch.Tensor]
    optimizer_state: Mapping[str, Any]
    test_reads_before_selection: int

    @property
    def complete(self) -> bool:
        return self.completed_epochs == self.total_epochs


def _validated_transition_matrices(
    transition_matrices: torch.Tensor,
    supervision: ActiveRowSupervision,
) -> torch.Tensor:
    expected = (*supervision.source_indices.shape, 3, 3)
    if transition_matrices.shape != expected:
        raise ValueError(f"transition matrices must have shape {expected}")
    if not torch.isfinite(transition_matrices).all() or torch.any(
        transition_matrices < 0.0
    ):
        raise ValueError("transition probabilities must be finite and nonnegative")
    row_error = torch.max(torch.abs(transition_matrices.sum(dim=-1) - 1.0))
    if row_error > 1e-12:
        raise ValueError("transition matrix rows must sum to one within 1e-12")
    return transition_matrices


def gather_active_transition_rows(
    transition_matrices: torch.Tensor,
    supervision: ActiveRowSupervision,
) -> torch.Tensor:
    """Gather realized source rows while keeping day zero masked."""

    matrices = _validated_transition_matrices(transition_matrices, supervision)
    safe_sources = torch.where(
        supervision.evaluation_mask,
        supervision.source_indices,
        torch.zeros_like(supervision.source_indices),
    ).to(device=matrices.device)
    gather_index = safe_sources[..., None, None].expand(-1, -1, 1, 3)
    return torch.gather(matrices, dim=2, index=gather_index).squeeze(2)


def active_row_brier_loss(
    transition_matrices: torch.Tensor,
    supervision: ActiveRowSupervision,
    *,
    sample_weights: torch.Tensor | None = None,
) -> torch.Tensor:
    """Return ordinary mean summed-coordinate Brier score on active rows."""

    rows = gather_active_transition_rows(transition_matrices, supervision)
    mask = supervision.evaluation_mask.to(device=rows.device)
    target = supervision.target_probabilities.to(
        dtype=rows.dtype, device=rows.device
    )
    losses = (rows[mask] - target[mask]).square().sum(dim=-1)
    if sample_weights is None:
        return losses.mean()
    weights = _validated_sample_weights(sample_weights, supervision, rows)
    if torch.all(weights == 1.0):
        return losses.mean()
    return (losses * weights).sum() / weights.sum()


def _validated_sample_weights(
    sample_weights: torch.Tensor,
    supervision: ActiveRowSupervision,
    reference: torch.Tensor,
) -> torch.Tensor:
    weights = torch.as_tensor(
        sample_weights, dtype=reference.dtype, device=reference.device
    )
    if weights.shape != supervision.source_indices.shape:
        raise ValueError("sample weights must have shape [block, day]")
    selected = weights[supervision.evaluation_mask.to(device=weights.device)]
    if (
        not torch.isfinite(selected).all()
        or selected.numel() == 0
        or torch.any(selected <= 0.0)
    ):
        raise ValueError("evaluated sample weights must be finite and positive")
    return selected


def active_row_cross_entropy_loss(
    transition_matrices: torch.Tensor,
    supervision: ActiveRowSupervision,
    *,
    sample_weights: torch.Tensor | None = None,
) -> torch.Tensor:
    """Return soft-target cross-entropy on the realized source row only."""

    rows = gather_active_transition_rows(transition_matrices, supervision)
    mask = supervision.evaluation_mask.to(device=rows.device)
    predicted = rows[mask]
    target = supervision.target_probabilities.to(
        dtype=rows.dtype, device=rows.device
    )[mask]
    tiny = torch.finfo(predicted.dtype).tiny
    losses = torch.where(
        target > 0.0,
        -target * torch.log(torch.clamp(predicted, min=tiny)),
        torch.zeros_like(target),
    ).sum(dim=-1)
    if sample_weights is None:
        return losses.mean()
    weights = _validated_sample_weights(sample_weights, supervision, rows)
    if torch.all(weights == 1.0):
        return losses.mean()
    return (losses * weights).sum() / weights.sum()


def build_age_source_balancing_weights(
    supervision: ActiveRowSupervision,
) -> torch.Tensor:
    """Build mean-one square-root inverse weights from one training split."""

    mask = supervision.evaluation_mask
    ages = supervision.regime_age_before_transition[mask]
    sources = supervision.source_indices[mask]
    age_groups = torch.where(
        ages < 30,
        torch.zeros_like(ages),
        torch.where(ages < 40, torch.ones_like(ages), torch.full_like(ages, 2)),
    )
    cell_indices = age_groups * 3 + sources
    counts = torch.bincount(cell_indices, minlength=9)
    selected_counts = counts[cell_indices]
    if torch.any(selected_counts <= 0):
        raise ValueError("evaluated age-source cells must have positive counts")
    selected = selected_counts.to(dtype=supervision.target_probabilities.dtype).rsqrt()
    selected = selected / selected.mean()
    weights = torch.zeros_like(
        supervision.target_probabilities[..., 0],
        dtype=supervision.target_probabilities.dtype,
    )
    weights[mask] = selected
    return weights


def _active_row_training_loss(
    transition_matrices: torch.Tensor,
    supervision: ActiveRowSupervision,
    *,
    training_objective: str,
    sample_weights: torch.Tensor | None,
) -> torch.Tensor:
    if training_objective == "active_row_brier":
        return active_row_brier_loss(
            transition_matrices,
            supervision,
            sample_weights=sample_weights,
        )
    if training_objective == "active_row_cross_entropy":
        return active_row_cross_entropy_loss(
            transition_matrices,
            supervision,
            sample_weights=sample_weights,
        )
    raise ValueError("unknown supervised probability training objective")


def score_probability_rollout(
    transition_matrices: torch.Tensor,
    supervision: ActiveRowSupervision,
) -> ProbabilityScores:
    """Score legal transition matrices against known active-source-row targets."""

    matrices = _validated_transition_matrices(transition_matrices, supervision)
    rows = gather_active_transition_rows(matrices, supervision)
    mask = supervision.evaluation_mask.to(device=rows.device)
    source = supervision.source_indices.to(device=rows.device)[mask]
    target = supervision.target_probabilities.to(
        dtype=rows.dtype, device=rows.device
    )[mask]
    predicted = rows[mask]
    ages = supervision.regime_age_before_transition.to(device=rows.device)[mask]
    squared_error = (predicted - target).square().sum(dim=-1)
    tiny = torch.finfo(predicted.dtype).tiny
    cross_entropy = torch.where(
        target > 0.0,
        -target * torch.log(torch.clamp(predicted, min=tiny)),
        torch.zeros_like(target),
    ).sum(dim=-1)
    source_probability = torch.gather(
        predicted, dim=-1, index=source.unsqueeze(-1)
    ).squeeze(-1)
    target_source_probability = torch.gather(
        target, dim=-1, index=source.unsqueeze(-1)
    ).squeeze(-1)
    predicted_hazard = 1.0 - source_probability
    oracle_hazard = 1.0 - target_source_probability
    hazard_error = torch.abs(predicted_hazard - oracle_hazard)

    bins = {
        "age_1_29": (ages >= 1) & (ages <= 29),
        "age_30_39": (ages >= 30) & (ages <= 39),
        "age_40_49": (ages >= 40) & (ages <= 49),
        "age_50_plus": ages >= 50,
    }
    age_metrics: dict[str, dict[str, int | float | None]] = {}
    for name, selected in bins.items():
        count = int(torch.count_nonzero(selected))
        age_metrics[name] = {
            "count": count,
            "oracle_brier": float(squared_error[selected].mean()) if count else None,
            "switch_hazard_mean_absolute_error": (
                float(hazard_error[selected].mean()) if count else None
            ),
            "mean_predicted_switch_hazard": (
                float(predicted_hazard[selected].mean()) if count else None
            ),
            "mean_oracle_switch_hazard": (
                float(oracle_hazard[selected].mean()) if count else None
            ),
        }
    maximum_row_error = float(torch.max(torch.abs(matrices.sum(dim=-1) - 1.0)))
    minimum_probability = float(torch.min(matrices))
    if not all(
        math.isfinite(value)
        for value in (
            float(squared_error.mean()),
            float(cross_entropy.mean()),
            float(hazard_error.mean()),
            maximum_row_error,
            minimum_probability,
        )
    ):
        raise ValueError("probability scores must be finite")
    return ProbabilityScores(
        evaluated_transition_count=int(torch.count_nonzero(mask)),
        switch_event_count=int(
            torch.count_nonzero(supervision.switch_event_mask)
        ),
        oracle_brier=float(squared_error.mean()),
        oracle_cross_entropy=float(cross_entropy.mean()),
        switch_hazard_mean_absolute_error=float(hazard_error.mean()),
        mean_predicted_switch_hazard=float(predicted_hazard.mean()),
        mean_oracle_switch_hazard=float(oracle_hazard.mean()),
        maximum_transition_row_sum_error=maximum_row_error,
        minimum_transition_probability=minimum_probability,
        age_bin_metrics=age_metrics,
    )


def _validate_observable_batch(observable: ObservableAssimilationBatch) -> None:
    if observable.forcing.ndim != 3 or observable.forcing.shape[-1] != 3:
        raise ValueError("observable forcing must have shape [block, day, 3]")
    blocks, forcing_days, _ = observable.forcing.shape
    days = int(observable.assimilation_days)
    if blocks <= 0 or days <= 0 or forcing_days < days:
        raise ValueError("observable batch must contain covered assimilation days")
    if (
        observable.observations.ndim != 2
        or observable.observations.shape[0] != blocks
        or observable.observations.shape[1] < days
    ):
        raise ValueError("observable observations must cover the assimilation days")
    if observable.initial_states.shape != (blocks, 15):
        raise ValueError("observable initial states must have shape [block, 15]")
    if observable.initial_covariances.shape != (blocks, 15, 15):
        raise ValueError(
            "observable initial covariances must have shape [block, 15, 15]"
        )
    for values, label in (
        (observable.forcing, "forcing"),
        (observable.observations, "observations"),
        (observable.initial_states, "initial states"),
        (observable.initial_covariances, "initial covariances"),
    ):
        if not torch.isfinite(values).all():
            raise ValueError(f"observable {label} must be finite")


def _validate_observable_supervision_pair(
    observable: ObservableAssimilationBatch,
    supervision: ActiveRowSupervision,
) -> None:
    _validate_observable_batch(observable)
    expected = (observable.forcing.shape[0], observable.assimilation_days)
    if supervision.source_indices.shape != expected:
        raise ValueError("observable and supervision block/day shapes must match")


def _initial_filter_values(
    observable: ObservableAssimilationBatch,
) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
    blocks = observable.forcing.shape[0]
    states = observable.initial_states.unsqueeze(1).expand(-1, 3, -1).clone()
    covariances = (
        observable.initial_covariances.unsqueeze(1)
        .expand(-1, 3, -1, -1)
        .clone()
    )
    probabilities = torch.full(
        (blocks, 3),
        1.0 / 3.0,
        dtype=observable.forcing.dtype,
        device=observable.forcing.device,
    )
    previous_forcing = torch.zeros(
        (blocks, 3),
        dtype=observable.forcing.dtype,
        device=observable.forcing.device,
    )
    previous_global_state = observable.initial_states.clone()
    return (
        states,
        covariances,
        probabilities,
        previous_forcing,
        previous_global_state,
    )


def fit_observable_feature_statistics(
    observable: ObservableAssimilationBatch,
    estimator: DifferentiableInteractingMultipleModel,
    fixed_transition: torch.Tensor,
    standard_deviation_floor: float = 1e-6,
) -> ObservableFeatureStatistics:
    """Fit feature normalization without truth, labels, validation, or test data."""

    _validate_observable_batch(observable)
    if not math.isfinite(standard_deviation_floor) or standard_deviation_floor <= 0.0:
        raise ValueError("standard deviation floor must be finite and positive")
    transition = torch.as_tensor(
        fixed_transition,
        dtype=observable.forcing.dtype,
        device=observable.forcing.device,
    )
    if (
        transition.shape != (3, 3)
        or not torch.isfinite(transition).all()
        or torch.any(transition <= 0.0)
    ):
        raise ValueError("fixed transition must be a finite positive 3 by 3 matrix")
    transition = transition / transition.sum(dim=-1, keepdim=True)
    expanded_transition = transition.expand(observable.forcing.shape[0], -1, -1)
    (
        states,
        covariances,
        probabilities,
        previous_forcing,
        previous_global_state,
    ) = _initial_filter_values(observable)
    features: list[torch.Tensor] = []
    estimator.eval()
    with torch.no_grad():
        for day in range(observable.assimilation_days):
            features.append(
                build_history_features(
                    previous_forcing,
                    previous_global_state,
                    probabilities,
                )
            )
            update = estimator.step(
                states=states,
                covariances=covariances,
                probabilities=probabilities,
                transition_matrix=expanded_transition,
                forcing=observable.forcing[:, day],
                observation=observable.observations[:, day],
            )
            states = update.posterior_states
            covariances = update.posterior_covariances
            probabilities = update.posterior_probabilities
            previous_forcing = observable.forcing[:, day]
            previous_global_state = update.global_posterior_states
    feature_tensor = torch.stack(features, dim=1).reshape(-1, FEATURE_COUNT)
    feature_mean = feature_tensor.mean(dim=0)
    feature_standard_deviation = torch.clamp(
        feature_tensor.std(dim=0, unbiased=False),
        min=float(standard_deviation_floor),
    )
    return ObservableFeatureStatistics(
        feature_mean=feature_mean,
        feature_standard_deviation=feature_standard_deviation,
    )


def rollout_history_probability(
    observable: ObservableAssimilationBatch,
    supervision: ActiveRowSupervision,
    network: HistoryTransitionNetwork,
    estimator: DifferentiableInteractingMultipleModel,
    *,
    training_objective: str = "active_row_brier",
    sample_weights: torch.Tensor | None = None,
) -> ProbabilityRolloutResult:
    """Roll out causal probabilities while stopping gradients at the filter."""

    _validate_observable_supervision_pair(observable, supervision)
    (
        states,
        covariances,
        probabilities,
        previous_forcing,
        previous_global_state,
    ) = _initial_filter_values(observable)
    hidden = network.initial_hidden(
        observable.forcing.shape[0],
        dtype=observable.forcing.dtype,
        device=observable.forcing.device,
    )
    transitions: list[torch.Tensor] = []
    estimator.eval()
    for day in range(observable.assimilation_days):
        previous_features = build_history_features(
            previous_forcing,
            previous_global_state,
            probabilities,
        )
        transition, hidden, _ = network(previous_features, hidden)
        transitions.append(transition)
        with torch.no_grad():
            update = estimator.step(
                states=states,
                covariances=covariances,
                probabilities=probabilities,
                transition_matrix=transition.detach(),
                forcing=observable.forcing[:, day],
                observation=observable.observations[:, day],
            )
            states = update.posterior_states.detach()
            covariances = update.posterior_covariances.detach()
            probabilities = update.posterior_probabilities.detach()
            previous_forcing = observable.forcing[:, day].detach()
            previous_global_state = update.global_posterior_states.detach()
    transition_tensor = torch.stack(transitions, dim=1)
    loss = _active_row_training_loss(
        transition_tensor,
        supervision,
        training_objective=training_objective,
        sample_weights=sample_weights,
    )
    scores = score_probability_rollout(transition_tensor.detach(), supervision)
    return ProbabilityRolloutResult(
        loss=loss,
        transition_matrices=transition_tensor,
        scores=scores,
        physical_filter_gradient_stopped=True,
    )


def _conditional_expected_ages(state: ModeDurationState) -> torch.Tensor:
    joint = state.joint_probabilities
    ages = torch.arange(
        1,
        joint.shape[-1] + 1,
        dtype=joint.dtype,
        device=joint.device,
    )
    marginals = joint.sum(dim=-1)
    weighted = (joint * ages.reshape(1, 1, -1)).sum(dim=-1)
    safe = torch.where(marginals > 0.0, marginals, torch.ones_like(marginals))
    expected = weighted / safe
    return torch.where(marginals > 0.0, expected, torch.ones_like(expected))


def rollout_semi_markov_probability(
    observable: ObservableAssimilationBatch,
    supervision: ActiveRowSupervision,
    network: CausalSemiMarkovTransitionModule,
    estimator: DifferentiableInteractingMultipleModel,
    *,
    training_objective: str = "active_row_brier",
    sample_weights: torch.Tensor | None = None,
) -> ProbabilityRolloutResult:
    """Roll out one causal mode-duration belief with a fixed day-zero prior."""

    _validate_observable_supervision_pair(observable, supervision)
    if observable.assimilation_days > network.maximum_age:
        raise ValueError("duration maximum age must cover all assimilation days")
    (
        states,
        covariances,
        probabilities,
        _,
        _,
    ) = _initial_filter_values(observable)
    blocks = observable.forcing.shape[0]
    base_transition = network.base_transition.expand(blocks, -1, -1)
    base_hazard = network.base_hazard.expand(blocks, 3)
    transitions: list[torch.Tensor] = []
    source_hazards: list[torch.Tensor] = []
    expected_ages: list[torch.Tensor] = []
    posterior_probabilities: list[torch.Tensor] = []
    duration_state: ModeDurationState | None = None
    final_age_hazards: torch.Tensor | None = None
    estimator.eval()

    for day in range(observable.assimilation_days):
        if day == 0:
            transition = base_transition
            source_hazard = base_hazard
            expected_age = torch.ones_like(probabilities)
            prediction = None
        else:
            if duration_state is None:
                raise RuntimeError("duration state was not initialized on day zero")
            prediction = network(duration_state)
            transition = prediction.transition_matrix
            source_hazard = prediction.source_hazards
            expected_age = _conditional_expected_ages(duration_state)
            final_age_hazards = prediction.age_hazards
        transitions.append(transition)
        source_hazards.append(source_hazard)
        expected_ages.append(expected_age)

        with torch.no_grad():
            update = estimator.step(
                states=states,
                covariances=covariances,
                probabilities=probabilities,
                transition_matrix=transition.detach(),
                forcing=observable.forcing[:, day],
                observation=observable.observations[:, day],
            )
            states = update.posterior_states.detach()
            covariances = update.posterior_covariances.detach()
            probabilities = update.posterior_probabilities.detach()
        posterior_probabilities.append(probabilities)
        if day == 0:
            duration_state = network.initial_state(probabilities)
        else:
            if prediction is None:
                raise RuntimeError("duration prediction is missing after day zero")
            duration_state = network.condition(prediction, probabilities)

    transition_tensor = torch.stack(transitions, dim=1)
    loss = _active_row_training_loss(
        transition_tensor,
        supervision,
        training_objective=training_objective,
        sample_weights=sample_weights,
    )
    scores = score_probability_rollout(transition_tensor.detach(), supervision)
    if final_age_hazards is None:
        # A one-day rollout is legal, although day zero is never evaluated.
        probe = network(
            network.initial_state(
                torch.full_like(probabilities, 1.0 / probabilities.shape[-1])
            )
        )
        final_age_hazards = probe.age_hazards
    return ProbabilityRolloutResult(
        loss=loss,
        transition_matrices=transition_tensor,
        scores=scores,
        physical_filter_gradient_stopped=True,
        duration_source_hazards=torch.stack(source_hazards, dim=1),
        duration_expected_ages=torch.stack(expected_ages, dim=1),
        posterior_mode_probabilities=torch.stack(
            posterior_probabilities, dim=1
        ),
        age_hazards=final_age_hazards,
    )


def rollout_static_probability(
    supervision: ActiveRowSupervision,
    network: StaticTransitionNetwork,
    *,
    dtype: torch.dtype,
    device: torch.device,
    training_objective: str = "active_row_brier",
    sample_weights: torch.Tensor | None = None,
) -> ProbabilityRolloutResult:
    """Repeat one learned matrix across blocks and days."""

    blocks, days = supervision.source_indices.shape
    features = torch.zeros((blocks, FEATURE_COUNT), dtype=dtype, device=device)
    hidden = network.initial_hidden(blocks, dtype=dtype, device=device)
    transition, _, _ = network(features, hidden)
    transition_tensor = transition.unsqueeze(1).expand(-1, days, -1, -1)
    loss = _active_row_training_loss(
        transition_tensor,
        supervision,
        training_objective=training_objective,
        sample_weights=sample_weights,
    )
    scores = score_probability_rollout(transition_tensor.detach(), supervision)
    return ProbabilityRolloutResult(
        loss=loss,
        transition_matrices=transition_tensor,
        scores=scores,
        physical_filter_gradient_stopped=True,
    )


def _probability_rollout_for_network(
    observable: ObservableAssimilationBatch,
    supervision: ActiveRowSupervision,
    network: (
        HistoryTransitionNetwork
        | StaticTransitionNetwork
        | CausalSemiMarkovTransitionModule
    ),
    estimator: DifferentiableInteractingMultipleModel,
    *,
    training_objective: str = "active_row_brier",
    sample_weights: torch.Tensor | None = None,
) -> ProbabilityRolloutResult:
    _validate_observable_supervision_pair(observable, supervision)
    if isinstance(network, StaticTransitionNetwork):
        return rollout_static_probability(
            supervision,
            network,
            dtype=observable.forcing.dtype,
            device=observable.forcing.device,
            training_objective=training_objective,
            sample_weights=sample_weights,
        )
    if isinstance(network, HistoryTransitionNetwork):
        return rollout_history_probability(
            observable,
            supervision,
            network,
            estimator,
            training_objective=training_objective,
            sample_weights=sample_weights,
        )
    if isinstance(network, CausalSemiMarkovTransitionModule):
        return rollout_semi_markov_probability(
            observable,
            supervision,
            network,
            estimator,
            training_objective=training_objective,
            sample_weights=sample_weights,
        )
    raise TypeError(
        "network must be a history, static, or causal duration transition network"
    )


def _validate_training_arguments(
    *,
    epochs: int,
    learning_rate: float,
    weight_decay: float,
    gradient_clip_norm: float,
) -> None:
    if isinstance(epochs, bool) or int(epochs) != epochs or int(epochs) <= 0:
        raise ValueError("epochs must be a positive integer")
    for value, label, allow_zero in (
        (learning_rate, "learning rate", False),
        (weight_decay, "weight decay", True),
        (gradient_clip_norm, "gradient clip norm", False),
    ):
        if not math.isfinite(value) or value < 0.0 or (not allow_zero and value == 0.0):
            raise ValueError(f"{label} is invalid")


def train_supervised_probability_chunk(
    training_observable: ObservableAssimilationBatch,
    training_supervision: ActiveRowSupervision,
    validation_observable: ObservableAssimilationBatch,
    validation_supervision: ActiveRowSupervision,
    network: (
        HistoryTransitionNetwork
        | StaticTransitionNetwork
        | CausalSemiMarkovTransitionModule
    ),
    estimator: DifferentiableInteractingMultipleModel,
    *,
    epochs: int,
    maximum_new_epochs: int,
    learning_rate: float,
    weight_decay: float,
    gradient_clip_norm: float,
    training_objective: str = "active_row_brier",
    training_sample_weights: torch.Tensor | None = None,
    resume_progress: ProbabilityTrainingProgress | None = None,
    progress_callback: Callable[[Mapping[str, float]], None] | None = None,
) -> ProbabilityTrainingProgress:
    """Advance a full-batch optimizer by a bounded number of whole epochs."""

    _validate_observable_supervision_pair(training_observable, training_supervision)
    _validate_observable_supervision_pair(
        validation_observable, validation_supervision
    )
    _validate_training_arguments(
        epochs=epochs,
        learning_rate=learning_rate,
        weight_decay=weight_decay,
        gradient_clip_norm=gradient_clip_norm,
    )
    if (
        isinstance(maximum_new_epochs, bool)
        or int(maximum_new_epochs) != maximum_new_epochs
        or int(maximum_new_epochs) <= 0
    ):
        raise ValueError("maximum new epochs must be a positive integer")
    optimizer = torch.optim.AdamW(
        network.parameters(),
        lr=float(learning_rate),
        weight_decay=float(weight_decay),
    )
    if resume_progress is None:
        completed_epochs = 0
        best_epoch = 0
        best_validation_brier = math.inf
        best_network_state: dict[str, torch.Tensor] = {}
        history: list[Mapping[str, float]] = []
    else:
        if (
            resume_progress.total_epochs != int(epochs)
            or resume_progress.completed_epochs < 0
            or resume_progress.completed_epochs >= int(epochs)
            or len(resume_progress.history) != resume_progress.completed_epochs
            or resume_progress.test_reads_before_selection != 0
        ):
            raise ValueError("resume progress is incompatible with requested training")
        network.load_state_dict(resume_progress.network_state)
        optimizer.load_state_dict(deepcopy(resume_progress.optimizer_state))
        completed_epochs = int(resume_progress.completed_epochs)
        best_epoch = int(resume_progress.best_epoch)
        best_validation_brier = float(resume_progress.best_validation_brier)
        best_network_state = {
            name: value.detach().clone()
            for name, value in resume_progress.best_network_state.items()
        }
        history = [dict(row) for row in resume_progress.history]
    final_epoch = min(
        int(epochs), completed_epochs + int(maximum_new_epochs)
    )
    for epoch in range(completed_epochs + 1, final_epoch + 1):
        started = time.perf_counter()
        network.train()
        optimizer.zero_grad(set_to_none=True)
        training_result = _probability_rollout_for_network(
            training_observable,
            training_supervision,
            network,
            estimator,
            training_objective=training_objective,
            sample_weights=training_sample_weights,
        )
        if not torch.isfinite(training_result.loss):
            raise FloatingPointError(
                "supervised probability training produced a non-finite loss"
            )
        training_result.loss.backward()
        gradients = [
            parameter.grad
            for parameter in network.parameters()
            if parameter.grad is not None
        ]
        if any(not torch.isfinite(gradient).all() for gradient in gradients):
            raise FloatingPointError(
                "supervised probability training produced non-finite gradients"
            )
        finite_gradient_maxima = [
            gradient.detach().abs().max() for gradient in gradients
        ]
        maximum_gradient = (
            max(float(value) for value in finite_gradient_maxima)
            if finite_gradient_maxima
            else 0.0
        )
        torch.nn.utils.clip_grad_norm_(
            network.parameters(), max_norm=float(gradient_clip_norm)
        )
        optimizer.step()

        network.eval()
        with torch.no_grad():
            validation_result = _probability_rollout_for_network(
                validation_observable,
                validation_supervision,
                network,
                estimator,
            )
        validation_brier = validation_result.scores.oracle_brier
        if validation_brier < best_validation_brier:
            best_epoch = epoch
            best_validation_brier = validation_brier
            best_network_state = {
                name: value.detach().clone()
                for name, value in network.state_dict().items()
            }
        epoch_record = {
            "epoch": float(epoch),
            "training_optimization_loss": float(training_result.loss.detach()),
                "training_oracle_brier": training_result.scores.oracle_brier,
                "training_oracle_cross_entropy": (
                    training_result.scores.oracle_cross_entropy
                ),
                "training_switch_hazard_mean_absolute_error": (
                    training_result.scores.switch_hazard_mean_absolute_error
                ),
                "validation_oracle_brier": validation_result.scores.oracle_brier,
                "validation_oracle_cross_entropy": (
                    validation_result.scores.oracle_cross_entropy
                ),
                "validation_switch_hazard_mean_absolute_error": (
                    validation_result.scores.switch_hazard_mean_absolute_error
                ),
                "maximum_absolute_gradient": maximum_gradient,
                "epoch_seconds": time.perf_counter() - started,
            }
        history.append(epoch_record)
        if progress_callback is not None:
            progress_callback(epoch_record)
    if best_epoch == 0 or not best_network_state:
        raise RuntimeError("training did not produce a finite validation checkpoint")
    return ProbabilityTrainingProgress(
        completed_epochs=final_epoch,
        total_epochs=int(epochs),
        best_epoch=best_epoch,
        best_validation_brier=best_validation_brier,
        history=tuple(history),
        best_network_state=best_network_state,
        network_state={
            name: value.detach().clone()
            for name, value in network.state_dict().items()
        },
        optimizer_state=deepcopy(optimizer.state_dict()),
        test_reads_before_selection=0,
    )


def train_supervised_probability(
    training_observable: ObservableAssimilationBatch,
    training_supervision: ActiveRowSupervision,
    validation_observable: ObservableAssimilationBatch,
    validation_supervision: ActiveRowSupervision,
    network: (
        HistoryTransitionNetwork
        | StaticTransitionNetwork
        | CausalSemiMarkovTransitionModule
    ),
    estimator: DifferentiableInteractingMultipleModel,
    *,
    epochs: int,
    learning_rate: float,
    weight_decay: float,
    gradient_clip_norm: float,
    training_objective: str = "active_row_brier",
    training_sample_weights: torch.Tensor | None = None,
    progress_callback: Callable[[Mapping[str, float]], None] | None = None,
) -> ProbabilityTrainingResult:
    """Select a direct-supervision checkpoint using validation Brier score."""

    progress = train_supervised_probability_chunk(
        training_observable,
        training_supervision,
        validation_observable,
        validation_supervision,
        network,
        estimator,
        epochs=epochs,
        maximum_new_epochs=epochs,
        learning_rate=learning_rate,
        weight_decay=weight_decay,
        gradient_clip_norm=gradient_clip_norm,
        training_objective=training_objective,
        training_sample_weights=training_sample_weights,
        progress_callback=progress_callback,
    )
    if not progress.complete:
        raise RuntimeError("unbounded training wrapper did not complete")
    return ProbabilityTrainingResult(
        best_epoch=progress.best_epoch,
        best_validation_brier=progress.best_validation_brier,
        history=progress.history,
        best_network_state=progress.best_network_state,
        test_reads_before_selection=progress.test_reads_before_selection,
    )
