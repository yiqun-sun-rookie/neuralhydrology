"""Long-history parameter-switch truth and preflight-only contracts."""

from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Mapping, Sequence

import numpy as np
import torch

from hbv_multilead_joint_uncertainty.synthetic_truth import generate_reference_truth

from .parameter_switch import (
    PARAMETER_IDS,
    _generate_one_truth,
    _validated_parameters,
)
from .synthetic import BlockSeeds, _forcing


@dataclass(frozen=True)
class LongHistorySchedule:
    """One realized schedule plus the known active-source-row probabilities."""

    mode_indices: np.ndarray
    active_source_indices: np.ndarray
    regime_age_before_transition: np.ndarray
    oracle_active_row_probabilities: np.ndarray
    transition_evaluation_mask: np.ndarray
    switch_event_mask: np.ndarray


@dataclass(frozen=True)
class ObservableAssimilationBatch:
    """Future strict-training view that structurally excludes synthetic truth."""

    forcing: torch.Tensor
    observations: torch.Tensor
    initial_states: torch.Tensor
    initial_covariances: torch.Tensor
    assimilation_days: int


@dataclass(frozen=True)
class LongHistoryParameterSwitchBatch:
    """Evaluation batch for continuous long-history parameter-switch truth."""

    forcing: torch.Tensor
    observations: torch.Tensor
    truth_states: torch.Tensor
    truth_discharge: torch.Tensor
    true_parameter_indices: torch.Tensor
    active_source_indices: torch.Tensor
    regime_age_before_transition: torch.Tensor
    oracle_active_row_probabilities: torch.Tensor
    transition_evaluation_mask: torch.Tensor
    switch_event_mask: torch.Tensor
    projection_adjustments: torch.Tensor
    process_perturbations: torch.Tensor
    initial_states: torch.Tensor
    initial_covariances: torch.Tensor
    block_ids: tuple[str, ...]
    block_seeds: tuple[BlockSeeds, ...]
    accepted_process_seeds: tuple[int, ...]
    rejected_process_seeds: tuple[int, ...]
    parameter_ids: tuple[str, str, str]
    warmup_parameter_id: str
    assimilation_days: int

    @property
    def true_process_indices(self) -> torch.Tensor:
        """Compatibility name for existing three-mode evaluation helpers."""

        return self.true_parameter_indices

    def as_observable(self) -> ObservableAssimilationBatch:
        """Return the only fields authorized for future strict training."""

        return ObservableAssimilationBatch(
            forcing=self.forcing,
            observations=self.observations,
            initial_states=self.initial_states,
            initial_covariances=self.initial_covariances,
            assimilation_days=self.assimilation_days,
        )


def _validated_hazard_values(hazard: Mapping[str, object]) -> dict[str, float | int]:
    required = {
        "early_age_maximum_exclusive",
        "early_hazard",
        "ramp_start_age",
        "ramp_end_age",
        "ramp_start_hazard",
        "ramp_slope_per_day",
        "late_hazard",
    }
    missing = required - set(hazard)
    if missing:
        raise ValueError(f"duration hazard is missing fields: {sorted(missing)}")
    values: dict[str, float | int] = {
        "early_age_maximum_exclusive": int(
            hazard["early_age_maximum_exclusive"]
        ),
        "early_hazard": float(hazard["early_hazard"]),
        "ramp_start_age": int(hazard["ramp_start_age"]),
        "ramp_end_age": int(hazard["ramp_end_age"]),
        "ramp_start_hazard": float(hazard["ramp_start_hazard"]),
        "ramp_slope_per_day": float(hazard["ramp_slope_per_day"]),
        "late_hazard": float(hazard["late_hazard"]),
    }
    if values["early_age_maximum_exclusive"] != values["ramp_start_age"]:
        raise ValueError("early hazard must end where the ramp starts")
    if int(values["ramp_start_age"]) <= 0 or int(values["ramp_end_age"]) < int(
        values["ramp_start_age"]
    ):
        raise ValueError("duration-hazard ages are invalid")
    probability_names = ("early_hazard", "ramp_start_hazard", "late_hazard")
    if any(
        not math.isfinite(float(values[name]))
        or float(values[name]) <= 0.0
        or float(values[name]) >= 1.0
        for name in probability_names
    ):
        raise ValueError("duration hazards must be finite probabilities")
    slope = float(values["ramp_slope_per_day"])
    ramp_end = float(values["ramp_start_hazard"]) + slope * (
        int(values["ramp_end_age"]) - int(values["ramp_start_age"])
    )
    if not math.isfinite(slope) or slope < 0.0 or ramp_end <= 0.0 or ramp_end >= 1.0:
        raise ValueError("duration-hazard ramp is invalid")
    if not math.isclose(
        ramp_end, float(values["late_hazard"]), rel_tol=0.0, abs_tol=1e-12
    ):
        raise ValueError("late hazard must equal the ramp endpoint")
    return values


def duration_dependent_switch_hazard(
    age: int, hazard: Mapping[str, object]
) -> float:
    """Return switch probability for the prior regime age before a transition."""

    if isinstance(age, bool) or int(age) != age or int(age) <= 0:
        raise ValueError("regime age must be a positive integer")
    values = _validated_hazard_values(hazard)
    integer_age = int(age)
    ramp_start = int(values["ramp_start_age"])
    ramp_end = int(values["ramp_end_age"])
    if integer_age < ramp_start:
        result = float(values["early_hazard"])
    elif integer_age <= ramp_end:
        result = float(values["ramp_start_hazard"]) + float(
            values["ramp_slope_per_day"]
        ) * (integer_age - ramp_start)
    else:
        result = float(values["late_hazard"])
    if result <= 0.0 or result >= 1.0:
        raise ValueError("calculated switch hazard is not a probability")
    return result


def duration_distribution_summary(
    hazard: Mapping[str, object], *, survival_tolerance: float = 1e-15
) -> dict[str, object]:
    """Calculate the exact discrete duration law implied by the hazard."""

    if (
        not math.isfinite(float(survival_tolerance))
        or survival_tolerance <= 0.0
        or survival_tolerance >= 1.0
    ):
        raise ValueError("survival tolerance must lie between zero and one")
    values = _validated_hazard_values(hazard)
    probabilities: list[float] = []
    survival = 1.0
    age = 1
    while survival > float(survival_tolerance):
        probability = duration_dependent_switch_hazard(age, values)
        probabilities.append(survival * probability)
        survival *= 1.0 - probability
        age += 1
        if age > 1_000_000:
            raise RuntimeError("duration distribution did not converge")
    probability_array = np.asarray(probabilities, dtype=np.float64)
    ages = np.arange(1, len(probabilities) + 1, dtype=np.float64)
    expected_duration = float(np.sum(ages * probability_array))
    cumulative = np.cumsum(probability_array)

    def quantile(probability: float) -> int:
        return int(np.searchsorted(cumulative, probability, side="left") + 1)

    ramp_start = int(values["ramp_start_age"])
    ramp_end = int(values["ramp_end_age"])
    early = float(probability_array[: ramp_start - 1].sum())
    middle = float(probability_array[ramp_start - 1 : ramp_end].sum())
    late = float(probability_array[ramp_end:].sum() + survival)
    return {
        "expected_duration_days": expected_duration,
        "long_run_switch_hazard": 1.0 / expected_duration,
        "long_run_stay_probability": 1.0 - 1.0 / expected_duration,
        "probability_switch_before_age_30": early,
        "probability_switch_age_30_through_50": middle,
        "probability_switch_after_age_50": late,
        "duration_quantiles_days": {
            "0.05": quantile(0.05),
            "0.50": quantile(0.50),
            "0.95": quantile(0.95),
            "0.99": quantile(0.99),
        },
        "calculated_through_age": len(probabilities),
        "remaining_survival_probability": survival,
    }


def transition_hazard_output_bounds(
    base_stay_probability: float, maximum_logit_correction: float
) -> dict[str, float]:
    """Bound total switch probability under independently bounded row logits."""

    stay = float(base_stay_probability)
    cap = float(maximum_logit_correction)
    if (
        not math.isfinite(stay)
        or stay <= 0.0
        or stay >= 1.0
        or not math.isfinite(cap)
        or cap <= 0.0
    ):
        raise ValueError("base stay probability and correction cap are invalid")
    base_hazard = 1.0 - stay
    logit_ratio = math.exp(2.0 * cap)
    minimum = base_hazard / (base_hazard + stay * logit_ratio)
    maximum = base_hazard * logit_ratio / (stay + base_hazard * logit_ratio)
    return {
        "base_stay_probability": stay,
        "base_total_switch_hazard": base_hazard,
        "maximum_logit_correction": cap,
        "minimum_total_switch_hazard": minimum,
        "maximum_total_switch_hazard": maximum,
    }


def generate_long_history_schedule(
    *, seed: int, total_days: int, hazard: Mapping[str, object]
) -> LongHistorySchedule:
    """Draw a continuous three-mode schedule from the frozen duration law."""

    if int(total_days) != total_days or int(total_days) < 2:
        raise ValueError("total_days must be an integer of at least two")
    _validated_hazard_values(hazard)
    days = int(total_days)
    generator = np.random.default_rng(int(seed))
    modes = np.empty(days, dtype=np.int64)
    sources = np.full(days, -1, dtype=np.int64)
    ages = np.zeros(days, dtype=np.int64)
    oracle_rows = np.zeros((days, 3), dtype=np.float64)
    evaluated = np.zeros(days, dtype=np.bool_)
    switched = np.zeros(days, dtype=np.bool_)

    modes[0] = int(generator.integers(0, 3))
    current_age = 1
    for day in range(1, days):
        source = int(modes[day - 1])
        switch_hazard = duration_dependent_switch_hazard(current_age, hazard)
        row = np.full(3, switch_hazard / 2.0, dtype=np.float64)
        row[source] = 1.0 - switch_hazard
        sources[day] = source
        ages[day] = current_age
        oracle_rows[day] = row
        evaluated[day] = True

        if float(generator.random()) < switch_hazard:
            alternatives = tuple(value for value in range(3) if value != source)
            destination = alternatives[int(generator.integers(0, 2))]
            switched[day] = True
            current_age = 1
        else:
            destination = source
            current_age += 1
        modes[day] = destination

    return LongHistorySchedule(
        mode_indices=modes,
        active_source_indices=sources,
        regime_age_before_transition=ages,
        oracle_active_row_probabilities=oracle_rows,
        transition_evaluation_mask=evaluated,
        switch_event_mask=switched,
    )


def generate_long_history_parameter_switch_batch(
    *,
    block_seeds: Sequence[BlockSeeds],
    parameter_candidates: Mapping[str, Mapping[str, float]],
    warmup_parameter_id: str,
    assimilation_days: int,
    maximum_forecast_lead: int,
    warmup_days: int,
    hazard: Mapping[str, object],
    process_standard_deviation: float,
    observation_standard_deviation: float,
    process_state_index: int = 4,
    require_zero_projection: bool = True,
    initial_covariance_fraction: float = 0.001,
    maximum_process_resamples: int = 100,
) -> LongHistoryParameterSwitchBatch:
    """Generate long histories without using a filter or a trainable network."""

    specifications = tuple(block_seeds)
    identifiers = tuple(str(value) for value in parameter_candidates)
    if identifiers != PARAMETER_IDS:
        raise ValueError(f"parameter candidates must use ordered identifiers {PARAMETER_IDS}")
    candidates = {
        identifier: _validated_parameters(parameter_candidates[identifier])
        for identifier in identifiers
    }
    if warmup_parameter_id not in candidates:
        raise ValueError("warmup parameter identifier is not a candidate")
    if not specifications or len({item.block_id for item in specifications}) != len(
        specifications
    ):
        raise ValueError("block specifications must be nonempty and uniquely named")
    if (
        int(assimilation_days) != assimilation_days
        or int(assimilation_days) <= 0
        or int(maximum_forecast_lead) != maximum_forecast_lead
        or int(maximum_forecast_lead) <= 0
        or int(warmup_days) != warmup_days
        or int(warmup_days) <= 0
        or not math.isfinite(float(process_standard_deviation))
        or float(process_standard_deviation) <= 0.0
        or not math.isfinite(float(observation_standard_deviation))
        or float(observation_standard_deviation) <= 0.0
        or not math.isfinite(float(initial_covariance_fraction))
        or float(initial_covariance_fraction) <= 0.0
        or int(maximum_process_resamples) != maximum_process_resamples
        or int(maximum_process_resamples) <= 0
    ):
        raise ValueError("generation lengths, deviations, and covariance are invalid")
    if int(process_state_index) not in (3, 4):
        raise ValueError("process state index must identify SUZ 3 or SLZ 4")
    _validated_hazard_values(hazard)

    total_days = int(assimilation_days) + int(maximum_forecast_lead)
    forcing_values: list[np.ndarray] = []
    observation_values: list[np.ndarray] = []
    state_values: list[np.ndarray] = []
    discharge_values: list[np.ndarray] = []
    mode_values: list[np.ndarray] = []
    source_values: list[np.ndarray] = []
    age_values: list[np.ndarray] = []
    oracle_values: list[np.ndarray] = []
    evaluation_values: list[np.ndarray] = []
    switch_values: list[np.ndarray] = []
    adjustment_values: list[np.ndarray] = []
    perturbation_values: list[np.ndarray] = []
    initial_states: list[np.ndarray] = []
    initial_covariances: list[np.ndarray] = []
    accepted_seeds: list[int] = []
    rejected_seeds: list[int] = []

    warmup_parameters = candidates[str(warmup_parameter_id)]
    for specification in specifications:
        complete_forcing = _forcing(
            specification.forcing_seed, int(warmup_days) + total_days
        )
        warmup_truth = generate_reference_truth(
            complete_forcing[: int(warmup_days)], warmup_parameters
        )
        initial_state = warmup_truth.states[-1].copy()
        active_forcing = complete_forcing[int(warmup_days) :]
        schedule = generate_long_history_schedule(
            seed=specification.schedule_seed,
            total_days=total_days,
            hazard=hazard,
        )

        truth = None
        accepted_seed = None
        for attempt in range(int(maximum_process_resamples)):
            candidate_seed = specification.process_seed + attempt * 1_000_000
            process_normals = np.random.default_rng(candidate_seed).standard_normal(
                total_days
            )
            try:
                truth = _generate_one_truth(
                    forcing=active_forcing,
                    initial_state=initial_state,
                    schedule_indices=schedule.mode_indices,
                    parameter_ids=identifiers,
                    parameter_candidates=candidates,
                    process_normals=process_normals,
                    process_standard_deviation=float(process_standard_deviation),
                    process_state_index=int(process_state_index),
                    require_zero_projection=bool(require_zero_projection),
                )
            except ValueError as error:
                if "projection" not in str(error):
                    raise
                rejected_seeds.append(candidate_seed)
                continue
            accepted_seed = candidate_seed
            break
        if truth is None or accepted_seed is None:
            raise RuntimeError(
                f"no admissible long-history truth found for {specification.block_id}"
            )

        observation_normals = np.random.default_rng(
            specification.observation_seed
        ).standard_normal(total_days)
        observations = truth["discharge"] + float(
            observation_standard_deviation
        ) * observation_normals
        scales = np.maximum(np.abs(initial_state), 1.0)
        initial_covariance = np.diag(
            np.square(float(initial_covariance_fraction) * scales)
        )

        forcing_values.append(active_forcing)
        observation_values.append(observations)
        state_values.append(truth["states"])
        discharge_values.append(truth["discharge"])
        mode_values.append(schedule.mode_indices)
        source_values.append(schedule.active_source_indices)
        age_values.append(schedule.regime_age_before_transition)
        oracle_values.append(schedule.oracle_active_row_probabilities)
        evaluation_values.append(schedule.transition_evaluation_mask)
        switch_values.append(schedule.switch_event_mask)
        adjustment_values.append(truth["projection_adjustments"])
        perturbation_values.append(truth["process_perturbations"])
        initial_states.append(initial_state)
        initial_covariances.append(initial_covariance)
        accepted_seeds.append(accepted_seed)

    def tensor(values: Sequence[np.ndarray], *, dtype: torch.dtype) -> torch.Tensor:
        return torch.as_tensor(np.stack(values), dtype=dtype).clone()

    return LongHistoryParameterSwitchBatch(
        forcing=tensor(forcing_values, dtype=torch.float64),
        observations=tensor(observation_values, dtype=torch.float64),
        truth_states=tensor(state_values, dtype=torch.float64),
        truth_discharge=tensor(discharge_values, dtype=torch.float64),
        true_parameter_indices=tensor(mode_values, dtype=torch.int64),
        active_source_indices=tensor(source_values, dtype=torch.int64),
        regime_age_before_transition=tensor(age_values, dtype=torch.int64),
        oracle_active_row_probabilities=tensor(oracle_values, dtype=torch.float64),
        transition_evaluation_mask=tensor(evaluation_values, dtype=torch.bool),
        switch_event_mask=tensor(switch_values, dtype=torch.bool),
        projection_adjustments=tensor(adjustment_values, dtype=torch.float64),
        process_perturbations=tensor(perturbation_values, dtype=torch.float64),
        initial_states=tensor(initial_states, dtype=torch.float64),
        initial_covariances=tensor(initial_covariances, dtype=torch.float64),
        block_ids=tuple(item.block_id for item in specifications),
        block_seeds=specifications,
        accepted_process_seeds=tuple(accepted_seeds),
        rejected_process_seeds=tuple(rejected_seeds),
        parameter_ids=identifiers,
        warmup_parameter_id=str(warmup_parameter_id),
        assimilation_days=int(assimilation_days),
    )
