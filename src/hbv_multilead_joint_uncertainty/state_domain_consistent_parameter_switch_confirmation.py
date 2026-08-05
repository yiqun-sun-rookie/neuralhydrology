"""Synthetic parameter switching with continuous, unprojected HBV-lite truth states."""

from __future__ import annotations

from dataclasses import dataclass
from itertools import combinations
from typing import Mapping, Sequence

import numpy as np
from scipy.stats import beta as beta_distribution

from hbv_joint_uncertainty.hbv_adapter import V1_PARAMETER_BOUNDS
from hbv_multilead_joint_uncertainty.methods import MethodCandidate, build_method_bank
from hbv_multilead_joint_uncertainty.synthetic_truth import (
    PARAMETER_NAMES,
    advance_reference_state,
    generate_reference_truth,
    project_reference_state,
    reference_routed_discharge,
)


STATE_COUNT = 15
LOWER_GROUNDWATER_STATE_INDEX = 4
DOMAIN_SETTING_PARAMETERS = ("parFC", "parCWH")


@dataclass(frozen=True)
class ParameterSwitchConfirmationResult:
    """All formal arrays required for reconstruction and independent audit."""

    block_ids: np.ndarray
    parameter_ids: np.ndarray
    forcing_blocks: np.ndarray
    parameter_schedule: np.ndarray
    process_standard_normals: np.ndarray
    observation_standard_normals: np.ndarray
    initial_states: np.ndarray
    initial_covariances: np.ndarray
    deterministic_truth_states: np.ndarray
    truth_process_perturbations: np.ndarray
    truth_projection_adjustments: np.ndarray
    switch_boundary_projection_adjustments: np.ndarray
    truth_states: np.ndarray
    truth_discharge: np.ndarray
    observations: np.ndarray
    posterior_probabilities: np.ndarray
    global_posterior_states: np.ndarray


def validate_parameter_candidates(
    parameter_vectors: Mapping[str, Mapping[str, float]],
) -> tuple[tuple[str, str, str], dict[str, dict[str, float]]]:
    """Validate three distinct candidates with identical truth-state limits."""
    identifiers = tuple(str(value) for value in parameter_vectors)
    if len(identifiers) != 3 or len(set(identifiers)) != 3:
        raise ValueError("parameter vectors must contain exactly three unique identifiers")
    validated: dict[str, dict[str, float]] = {}
    for identifier in identifiers:
        raw = parameter_vectors[identifier]
        if set(raw) != set(PARAMETER_NAMES):
            raise ValueError(
                f"parameter candidate {identifier} must contain exactly thirteen values"
            )
        values = {name: float(raw[name]) for name in PARAMETER_NAMES}
        if not np.all(np.isfinite(tuple(values.values()))):
            raise ValueError(f"parameter candidate {identifier} must be finite")
        for name, value in values.items():
            lower, upper = V1_PARAMETER_BOUNDS[name]
            if value < lower or value > upper:
                raise ValueError(
                    f"parameter candidate {identifier} has {name} outside frozen bounds"
                )
        validated[identifier] = values

    for name in DOMAIN_SETTING_PARAMETERS:
        shared = np.asarray(
            [validated[identifier][name] for identifier in identifiers],
            dtype=np.float64,
        )
        if not np.all(shared == shared[0]):
            raise ValueError(f"all parameter candidates must use the same {name}")

    vectors = np.asarray(
        [[validated[identifier][name] for name in PARAMETER_NAMES] for identifier in identifiers],
        dtype=np.float64,
    )
    for left, right in combinations(range(3), 2):
        if np.array_equal(vectors[left], vectors[right]):
            raise ValueError("parameter candidates must be distinct")
    return identifiers, validated


def build_rotating_parameter_schedule(
    parameter_ids: Sequence[str], stage_length_days: int
) -> np.ndarray:
    """Build three balanced cyclic schedules with two switches per trial."""
    identifiers = tuple(str(value) for value in parameter_ids)
    if len(identifiers) != 3 or len(set(identifiers)) != 3:
        raise ValueError("parameter_ids must contain exactly three unique identifiers")
    if (
        isinstance(stage_length_days, bool)
        or not isinstance(stage_length_days, (int, np.integer))
        or int(stage_length_days) <= 0
    ):
        raise ValueError("stage_length_days must be a positive integer")
    length = int(stage_length_days)
    orders = (
        (identifiers[1], identifiers[2], identifiers[0]),
        (identifiers[2], identifiers[0], identifiers[1]),
        (identifiers[0], identifiers[1], identifiers[2]),
    )
    return np.asarray(
        [[identifier for identifier in order for _ in range(length)] for order in orders],
        dtype=np.str_,
    )


def build_fixed_lower_groundwater_covariance(
    standard_deviation_mm_day: float,
) -> np.ndarray:
    """Return one covariance supported only on lower groundwater storage."""
    standard_deviation = float(standard_deviation_mm_day)
    if not np.isfinite(standard_deviation) or standard_deviation <= 0.0:
        raise ValueError("process standard deviation must be finite and positive")
    covariance = np.zeros((STATE_COUNT, STATE_COUNT), dtype=np.float64)
    covariance[
        LOWER_GROUNDWATER_STATE_INDEX, LOWER_GROUNDWATER_STATE_INDEX
    ] = standard_deviation**2
    return covariance


def _initial_covariance(initial_state: np.ndarray, covariance_fraction: float) -> np.ndarray:
    fraction = float(covariance_fraction)
    if not np.isfinite(fraction) or fraction <= 0.0:
        raise ValueError("initial covariance fraction must be finite and positive")
    scales = np.maximum(np.abs(np.asarray(initial_state, dtype=np.float64)), 1.0)
    return np.diag(np.square(fraction * scales))


def audit_candidate_distinguishability(
    forcing_blocks,
    parameter_vectors: Mapping[str, Mapping[str, float]],
    warmup_days: int,
    observation_standard_deviation: float,
    minimum_observation_standard_deviation_multiple: float,
    minimum_center_standard_deviation_multiple: float,
    center_parameter_index: int = 1,
) -> list[dict]:
    """Audit deterministic discharge separation on development-only forcing."""
    identifiers, parameters = validate_parameter_candidates(parameter_vectors)
    forcing = np.asarray(forcing_blocks, dtype=np.float64)
    warmup = int(warmup_days)
    if (
        forcing.ndim != 3
        or forcing.shape[2] != 3
        or forcing.shape[1] <= warmup
        or warmup <= 0
        or not np.all(np.isfinite(forcing))
    ):
        raise ValueError("candidate-construction forcing has an invalid shape")
    if center_parameter_index < 0 or center_parameter_index >= 3:
        raise ValueError("center_parameter_index must identify one candidate")
    observation_std = float(observation_standard_deviation)
    minimum_observation = float(minimum_observation_standard_deviation_multiple)
    minimum_center = float(minimum_center_standard_deviation_multiple)
    if (
        not np.isfinite(observation_std)
        or observation_std <= 0.0
        or not np.isfinite(minimum_observation)
        or minimum_observation <= 0.0
        or not np.isfinite(minimum_center)
        or minimum_center <= 0.0
    ):
        raise ValueError("candidate distinguishability thresholds must be positive")

    candidate_discharge = np.empty(
        (len(identifiers), forcing.shape[0], forcing.shape[1] - warmup),
        dtype=np.float64,
    )
    maximum_start_projection = 0.0
    reference_parameters = parameters[identifiers[center_parameter_index]]
    for block in range(forcing.shape[0]):
        warmup_truth = generate_reference_truth(
            forcing[block, :warmup], reference_parameters
        )
        initial_state = warmup_truth.states[-1].copy()
        for candidate_index, identifier in enumerate(identifiers):
            state = initial_state.copy()
            candidate_parameters = parameters[identifier]
            for day, (rain, potential_evaporation, temperature) in enumerate(
                forcing[block, warmup:]
            ):
                projected = project_reference_state(state, candidate_parameters)
                maximum_start_projection = max(
                    maximum_start_projection,
                    float(np.max(np.abs(projected - state))),
                )
                state = advance_reference_state(
                    state,
                    float(rain),
                    float(potential_evaporation),
                    float(temperature),
                    candidate_parameters,
                )
                candidate_discharge[candidate_index, block, day] = (
                    reference_routed_discharge(
                        state, candidate_parameters["lag_time"]
                    )
                )

    center_standard_deviation = float(
        np.std(candidate_discharge[center_parameter_index], ddof=1)
    )
    if center_standard_deviation <= 0.0 or not np.isfinite(center_standard_deviation):
        raise ValueError("trained-center discharge standard deviation is invalid")
    rows: list[dict] = []
    for left, right in combinations(range(3), 2):
        root_mean_square_difference = float(
            np.sqrt(
                np.mean(
                    np.square(candidate_discharge[left] - candidate_discharge[right])
                )
            )
        )
        observation_ratio = root_mean_square_difference / observation_std
        center_ratio = root_mean_square_difference / center_standard_deviation
        rows.append(
            {
                "left_parameter_id": identifiers[left],
                "right_parameter_id": identifiers[right],
                "pairwise_discharge_rmse": root_mean_square_difference,
                "rmse_in_observation_standard_deviations": observation_ratio,
                "rmse_as_center_discharge_standard_deviation": center_ratio,
                "minimum_required_observation_standard_deviations": minimum_observation,
                "minimum_required_center_standard_deviation": minimum_center,
                "maximum_daily_start_projection_adjustment": maximum_start_projection,
                "passed": (
                    observation_ratio >= minimum_observation
                    and center_ratio >= minimum_center
                    and maximum_start_projection == 0.0
                ),
            }
        )
    return rows


def generate_parameter_switch_truth(
    forcing,
    parameter_vectors: Mapping[str, Mapping[str, float]],
    initial_state,
    parameter_schedule,
    process_standard_deviation_mm_day: float,
    lower_groundwater_standard_normals,
) -> dict[str, np.ndarray]:
    """Generate switched truth while rejecting every external state projection."""
    identifiers, parameters = validate_parameter_candidates(parameter_vectors)
    forcing_values = np.asarray(forcing, dtype=np.float64)
    schedule = np.asarray(parameter_schedule).astype(str)
    normals = np.asarray(lower_groundwater_standard_normals, dtype=np.float64)
    state = np.asarray(initial_state, dtype=np.float64).copy()
    standard_deviation = float(process_standard_deviation_mm_day)
    if (
        forcing_values.ndim != 2
        or forcing_values.shape[1] != 3
        or len(forcing_values) == 0
        or not np.all(np.isfinite(forcing_values))
    ):
        raise ValueError("forcing must be one nonempty finite days-by-three array")
    day_count = len(forcing_values)
    if schedule.shape != (day_count,) or normals.shape != (day_count,):
        raise ValueError("parameter schedule and normals must match forcing days")
    if set(schedule) - set(identifiers):
        raise ValueError("parameter schedule contains an unknown identifier")
    if state.shape != (STATE_COUNT,) or not np.all(np.isfinite(state)):
        raise ValueError("initial_state must be one finite fifteen-state vector")
    if (
        not np.isfinite(standard_deviation)
        or standard_deviation <= 0.0
        or not np.all(np.isfinite(normals))
    ):
        raise ValueError("process standard deviation and normals must be finite")

    deterministic = np.empty((day_count, STATE_COUNT), dtype=np.float64)
    perturbations = np.zeros((day_count, STATE_COUNT), dtype=np.float64)
    projection_adjustments = np.empty((day_count, STATE_COUNT), dtype=np.float64)
    boundary_adjustments = np.zeros((day_count, STATE_COUNT), dtype=np.float64)
    states = np.empty((day_count, STATE_COUNT), dtype=np.float64)
    discharge = np.empty(day_count, dtype=np.float64)

    for day, (rain, potential_evaporation, temperature) in enumerate(forcing_values):
        identifier = schedule[day]
        active_parameters = parameters[identifier]
        if day > 0 and schedule[day] != schedule[day - 1]:
            projected_at_boundary = project_reference_state(state, active_parameters)
            boundary_adjustment = projected_at_boundary - state
            boundary_adjustments[day] = boundary_adjustment
            if np.any(boundary_adjustment != 0.0):
                raise ValueError(
                    "switch-boundary state gate failed: the unchanged truth state "
                    "would require projection under the new parameters"
                )

        deterministic_state = advance_reference_state(
            state,
            float(rain),
            float(potential_evaporation),
            float(temperature),
            active_parameters,
        )
        perturbation = np.zeros(STATE_COUNT, dtype=np.float64)
        perturbation[LOWER_GROUNDWATER_STATE_INDEX] = (
            normals[day] * standard_deviation
        )
        unprojected_state = deterministic_state + perturbation
        projected_state = project_reference_state(unprojected_state, active_parameters)
        adjustment = projected_state - unprojected_state
        if np.any(adjustment != 0.0):
            raise ValueError(
                "truth transition gate failed: a process-noise realization would "
                "require state projection"
            )

        deterministic[day] = deterministic_state
        perturbations[day] = perturbation
        projection_adjustments[day] = adjustment
        state = unprojected_state
        states[day] = state
        discharge[day] = reference_routed_discharge(
            state, active_parameters["lag_time"]
        )

    return {
        "deterministic_states": deterministic,
        "process_perturbations": perturbations,
        "projection_adjustments": projection_adjustments,
        "switch_boundary_projection_adjustments": boundary_adjustments,
        "states": states,
        "discharge": discharge,
    }


def first_complete_clear_dominance_run(
    probabilities,
    true_candidate_index: int,
    consecutive_days: int,
    window_days: int,
    minimum_probability_exclusive: float,
    minimum_margin_inclusive: float,
) -> int | None:
    """Return the first complete run satisfying probability and margin gates."""
    values = np.asarray(probabilities, dtype=np.float64)
    if values.ndim != 2 or values.shape[1] != 3:
        raise ValueError("probabilities must have day and three-candidate dimensions")
    if (
        not np.all(np.isfinite(values))
        or np.any(values < 0.0)
        or not np.allclose(values.sum(axis=1), 1.0, rtol=0.0, atol=1e-12)
    ):
        raise ValueError("probabilities must be finite, nonnegative, and normalized")
    index = int(true_candidate_index)
    run_length = int(consecutive_days)
    window = int(window_days)
    probability_threshold = float(minimum_probability_exclusive)
    margin_threshold = float(minimum_margin_inclusive)
    if (
        index < 0
        or index >= 3
        or run_length <= 0
        or window < run_length
        or len(values) < window
        or probability_threshold <= 0.0
        or probability_threshold >= 1.0
        or margin_threshold < 0.0
        or margin_threshold >= 1.0
    ):
        raise ValueError("clear-dominance response thresholds are invalid")
    true_probability = values[:window, index]
    runner_up = np.max(np.delete(values[:window], index, axis=1), axis=1)
    clear = (true_probability > probability_threshold) & (
        true_probability - runner_up >= margin_threshold
    )
    for start in range(window - run_length + 1):
        if bool(np.all(clear[start : start + run_length])):
            return start
    return None


def exact_binomial_interval(
    successes: int, total: int, confidence_level: float = 0.95
) -> tuple[float, float]:
    """Return the two-sided exact Clopper-Pearson binomial interval."""
    if (
        isinstance(successes, bool)
        or isinstance(total, bool)
        or not isinstance(successes, (int, np.integer))
        or not isinstance(total, (int, np.integer))
        or int(total) <= 0
        or int(successes) < 0
        or int(successes) > int(total)
    ):
        raise ValueError("successes and total must define a valid binomial count")
    confidence = float(confidence_level)
    if not np.isfinite(confidence) or confidence <= 0.0 or confidence >= 1.0:
        raise ValueError("confidence_level must be strictly between zero and one")
    count = int(successes)
    size = int(total)
    alpha = 1.0 - confidence
    lower = (
        0.0
        if count == 0
        else float(beta_distribution.ppf(alpha / 2.0, count, size - count + 1))
    )
    upper = (
        1.0
        if count == size
        else float(
            beta_distribution.ppf(
                1.0 - alpha / 2.0, count + 1, size - count
            )
        )
    )
    return lower, upper


def _directed_transition_order(
    parameter_ids: Sequence[str],
) -> tuple[tuple[str, str], ...]:
    identifiers = tuple(str(value) for value in parameter_ids)
    if len(identifiers) != 3 or len(set(identifiers)) != 3:
        raise ValueError("parameter_ids must contain exactly three unique identifiers")
    return (
        (identifiers[0], identifiers[1]),
        (identifiers[1], identifiers[2]),
        (identifiers[2], identifiers[0]),
    )


def summarize_parameter_switch_response(
    probabilities,
    parameter_schedule,
    parameter_ids: Sequence[str],
    response_window_days: int,
    consecutive_clear_days: int,
    minimum_probability_exclusive: float,
    minimum_margin_inclusive: float,
    minimum_successful_events: int,
    minimum_interval_lower_bound: float,
) -> tuple[list[dict], list[dict]]:
    """Score prospectively frozen clear posterior dominance after each switch."""
    identifiers = tuple(str(value) for value in parameter_ids)
    if len(identifiers) != 3 or len(set(identifiers)) != 3:
        raise ValueError("parameter_ids must contain exactly three unique identifiers")
    values = np.asarray(probabilities, dtype=np.float64)
    schedule = np.asarray(parameter_schedule).astype(str)
    if values.ndim != 4 or values.shape[-1] != 3:
        raise ValueError(
            "probabilities must have block, truth-trial, day, candidate dimensions"
        )
    block_count, trial_count, day_count, _ = values.shape
    if schedule.shape != (trial_count, day_count):
        raise ValueError("parameter schedule shape must match truth trials and days")
    if (
        not np.all(np.isfinite(values))
        or np.any(values < 0.0)
        or not np.allclose(values.sum(axis=-1), 1.0, rtol=0.0, atol=1e-12)
    ):
        raise ValueError("probabilities must be finite, nonnegative, and normalized")
    window = int(response_window_days)
    consecutive = int(consecutive_clear_days)
    minimum = int(minimum_successful_events)
    lower_bound = float(minimum_interval_lower_bound)
    candidate_index = {
        identifier: index for index, identifier in enumerate(identifiers)
    }

    events: list[dict] = []
    for block in range(block_count):
        for trial in range(trial_count):
            boundaries = np.flatnonzero(
                schedule[trial, 1:] != schedule[trial, :-1]
            ) + 1
            for boundary in boundaries:
                if boundary + window > day_count:
                    raise ValueError("response window extends beyond saved days")
                old_identifier = str(schedule[trial, boundary - 1])
                new_identifier = str(schedule[trial, boundary])
                new_index = candidate_index[new_identifier]
                response_values = values[
                    block, trial, boundary : boundary + window
                ]
                response_start = first_complete_clear_dominance_run(
                    response_values,
                    true_candidate_index=new_index,
                    consecutive_days=consecutive,
                    window_days=window,
                    minimum_probability_exclusive=minimum_probability_exclusive,
                    minimum_margin_inclusive=minimum_margin_inclusive,
                )
                true_probability = response_values[:, new_index]
                runner_up = np.max(
                    np.delete(response_values, new_index, axis=1), axis=1
                )
                event = {
                    "event_id": (
                        f"block_{block + 1:02d}_trial_{trial + 1}_"
                        f"switch_day_{boundary + 1}"
                    ),
                    "block_index": block,
                    "trial_index": trial,
                    "switch_day_index": int(boundary),
                    "switch_day_number": int(boundary + 1),
                    "old_parameter_id": old_identifier,
                    "new_parameter_id": new_identifier,
                    "transition_label": f"{old_identifier}_to_{new_identifier}",
                    "numerical_success": response_start is not None,
                    "response_start_day": (
                        None if response_start is None else int(response_start)
                    ),
                    "new_candidate_top_ranked_days_in_window": int(
                        np.count_nonzero(
                            np.argmax(response_values, axis=1) == new_index
                        )
                    ),
                    "new_candidate_probability_above_half_days_in_window": int(
                        np.count_nonzero(true_probability > 0.5)
                    ),
                    "minimum_new_candidate_probability_in_window": float(
                        np.min(true_probability)
                    ),
                    "maximum_new_candidate_probability_in_window": float(
                        np.max(true_probability)
                    ),
                    "minimum_probability_margin_in_window": float(
                        np.min(true_probability - runner_up)
                    ),
                    "maximum_probability_margin_in_window": float(
                        np.max(true_probability - runner_up)
                    ),
                }
                if response_start is None:
                    event["minimum_probability_in_qualifying_run"] = None
                    event["minimum_margin_in_qualifying_run"] = None
                else:
                    selected = slice(response_start, response_start + consecutive)
                    event["minimum_probability_in_qualifying_run"] = float(
                        np.min(true_probability[selected])
                    )
                    event["minimum_margin_in_qualifying_run"] = float(
                        np.min((true_probability - runner_up)[selected])
                    )
                events.append(event)

    summaries: list[dict] = []
    for old_identifier, new_identifier in _directed_transition_order(identifiers):
        selected = [
            row
            for row in events
            if row["old_parameter_id"] == old_identifier
            and row["new_parameter_id"] == new_identifier
        ]
        successes = sum(bool(row["numerical_success"]) for row in selected)
        event_count = len(selected)
        if event_count == 0:
            raise ValueError("one frozen directed transition has no events")
        lower, upper = exact_binomial_interval(successes, event_count)
        response_starts = [
            int(row["response_start_day"])
            for row in selected
            if row["response_start_day"] is not None
        ]
        summaries.append(
            {
                "old_parameter_id": old_identifier,
                "new_parameter_id": new_identifier,
                "transition_label": f"{old_identifier}_to_{new_identifier}",
                "event_count": event_count,
                "numerically_successful_event_count": successes,
                "numerical_response_fraction": successes / event_count,
                "exact_interval_lower": lower,
                "exact_interval_upper": upper,
                "median_response_start_day": (
                    None
                    if not response_starts
                    else float(np.median(response_starts))
                ),
                "maximum_response_start_day": (
                    None if not response_starts else int(max(response_starts))
                ),
                "numerical_criterion_passed": (
                    successes >= minimum and lower > lower_bound
                ),
            }
        )
    return events, summaries


def summarize_full_stage_accuracy(
    probabilities, parameter_schedule, parameter_ids: Sequence[str]
) -> list[dict]:
    """Return descriptive all-day posterior accuracy for each true candidate."""
    identifiers = tuple(str(value) for value in parameter_ids)
    values = np.asarray(probabilities, dtype=np.float64)
    schedule = np.asarray(parameter_schedule).astype(str)
    if values.ndim != 4 or schedule.shape != values.shape[1:3]:
        raise ValueError("stage-accuracy inputs have incompatible shapes")
    candidate_index = {
        identifier: index for index, identifier in enumerate(identifiers)
    }
    top = np.argmax(values, axis=-1)
    rows: list[dict] = []
    for identifier in identifiers:
        trial_day_mask = schedule == identifier
        mask = np.broadcast_to(trial_day_mask, values.shape[:3])
        true_index = candidate_index[identifier]
        count = int(np.count_nonzero(mask))
        rows.append(
            {
                "true_parameter_id": identifier,
                "day_count": count,
                "top_ranked_day_count": int(
                    np.count_nonzero((top == true_index) & mask)
                ),
                "top_ranked_fraction": float(np.mean(top[mask] == true_index)),
                "mean_true_candidate_probability": float(
                    np.mean(values[..., true_index][mask])
                ),
            }
        )
    return rows


def run_parameter_switch_confirmation(
    forcing_blocks,
    block_ids: Sequence[str],
    parameter_vectors: Mapping[str, Mapping[str, float]],
    process_noise_seeds: Sequence[int],
    observation_noise_seeds: Sequence[int],
    warmup_days: int,
    stage_length_days: int,
    initial_covariance_fraction: float,
    process_standard_deviation_mm_day: float,
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
) -> ParameterSwitchConfirmationResult:
    """Generate continuous switched truths and assimilate without forecasting."""
    identifiers, parameters = validate_parameter_candidates(parameter_vectors)
    forcing = np.asarray(forcing_blocks, dtype=np.float64)
    block_labels = tuple(str(value) for value in block_ids)
    process_seeds = tuple(int(value) for value in process_noise_seeds)
    observation_seeds = tuple(int(value) for value in observation_noise_seeds)
    warmup = int(warmup_days)
    stage_length = int(stage_length_days)
    assimilation_days = stage_length * 3
    block_count = len(block_labels)
    if (
        forcing.shape != (block_count, warmup + assimilation_days, 3)
        or block_count == 0
        or not np.all(np.isfinite(forcing))
    ):
        raise ValueError("forcing blocks do not match the frozen experiment shape")
    if (
        len(set(block_labels)) != block_count
        or len(process_seeds) != block_count
        or len(observation_seeds) != block_count
        or len(set(process_seeds)) != block_count
        or len(set(observation_seeds)) != block_count
    ):
        raise ValueError("block labels and noise seeds must be unique and matched")
    observation_std = float(observation_standard_deviation)
    process_std = float(process_standard_deviation_mm_day)
    if (
        not np.isfinite(observation_std)
        or observation_std <= 0.0
        or not np.isfinite(process_std)
        or process_std <= 0.0
    ):
        raise ValueError("noise standard deviations must be finite and positive")

    covariance = build_fixed_lower_groundwater_covariance(process_std)
    process_id = "fixed_lower_groundwater_sd_1"
    candidates = tuple(
        MethodCandidate(
            candidate_id=f"{identifier}__{process_id}",
            parameter_id=identifier,
            process_id=process_id,
            process_scale=process_std**2,
            parameters=parameters[identifier].copy(),
            process_covariance=covariance.copy(),
        )
        for identifier in identifiers
    )
    schedule = build_rotating_parameter_schedule(identifiers, stage_length)
    process_normals = np.empty((block_count, assimilation_days), dtype=np.float64)
    observation_normals = np.empty_like(process_normals)
    initial_states = np.empty((block_count, STATE_COUNT), dtype=np.float64)
    initial_covariances = np.empty(
        (block_count, STATE_COUNT, STATE_COUNT), dtype=np.float64
    )
    truth_shape = (block_count, 3, assimilation_days, STATE_COUNT)
    deterministic_truth = np.empty(truth_shape, dtype=np.float64)
    perturbations = np.empty(truth_shape, dtype=np.float64)
    projection_adjustments = np.empty(truth_shape, dtype=np.float64)
    boundary_adjustments = np.empty(truth_shape, dtype=np.float64)
    truth_states = np.empty(truth_shape, dtype=np.float64)
    truth_discharge = np.empty((block_count, 3, assimilation_days), dtype=np.float64)
    observations = np.empty_like(truth_discharge)
    probabilities = np.empty(
        (block_count, 3, assimilation_days, 3), dtype=np.float64
    )
    global_states = np.empty(truth_shape, dtype=np.float64)

    reference_parameters = parameters[identifiers[1]]
    for block in range(block_count):
        process_normals[block] = np.random.default_rng(
            process_seeds[block]
        ).standard_normal(assimilation_days)
        observation_normals[block] = np.random.default_rng(
            observation_seeds[block]
        ).standard_normal(assimilation_days)
        warmup_truth = generate_reference_truth(
            forcing[block, :warmup], reference_parameters
        )
        initial_state = warmup_truth.states[-1].copy()
        initial_states[block] = initial_state
        initial_covariance = _initial_covariance(
            initial_state, initial_covariance_fraction
        )
        initial_covariances[block] = initial_covariance
        active_forcing = forcing[block, warmup:]

        for trial in range(3):
            truth = generate_parameter_switch_truth(
                active_forcing,
                parameters,
                initial_state,
                schedule[trial],
                process_std,
                process_normals[block],
            )
            deterministic_truth[block, trial] = truth["deterministic_states"]
            perturbations[block, trial] = truth["process_perturbations"]
            projection_adjustments[block, trial] = truth["projection_adjustments"]
            boundary_adjustments[block, trial] = truth[
                "switch_boundary_projection_adjustments"
            ]
            truth_states[block, trial] = truth["states"]
            truth_discharge[block, trial] = truth["discharge"]
            observations[block, trial] = (
                truth["discharge"] + observation_std * observation_normals[block]
            )

            initial_state_by_candidate = {
                identifier: initial_state for identifier in identifiers
            }
            bank = build_method_bank(
                candidates=candidates,
                initial_states=initial_state_by_candidate,
                initial_covariance=initial_covariance,
                observation_standard_deviation=observation_std,
                factor_transition_stay_probability=factor_transition_stay_probability,
                interaction_mode="full",
            )
            for day in range(assimilation_days):
                rain, potential_evaporation, temperature = active_forcing[day]
                for transition in bank.transitions:
                    transition.set_forcing(
                        float(rain),
                        float(potential_evaporation),
                        float(temperature),
                    )
                step = bank.estimator.step(observations[block, trial, day])
                probabilities[block, trial, day] = step.posterior_probabilities
                global_states[block, trial, day] = step.global_posterior_state

    arrays = (
        forcing,
        process_normals,
        observation_normals,
        initial_states,
        initial_covariances,
        deterministic_truth,
        perturbations,
        projection_adjustments,
        boundary_adjustments,
        truth_states,
        truth_discharge,
        observations,
        probabilities,
        global_states,
    )
    if not all(np.all(np.isfinite(values)) for values in arrays):
        raise FloatingPointError("experiment produced a non-finite array")
    if np.any(projection_adjustments != 0.0):
        raise ValueError("truth transition projection gate failed")
    if np.any(boundary_adjustments != 0.0):
        raise ValueError("switch-boundary projection gate failed")
    if not np.allclose(
        probabilities.sum(axis=-1), 1.0, rtol=0.0, atol=1e-12
    ):
        raise FloatingPointError("posterior probabilities are not normalized")

    return ParameterSwitchConfirmationResult(
        block_ids=np.asarray(block_labels, dtype=np.str_),
        parameter_ids=np.asarray(identifiers, dtype=np.str_),
        forcing_blocks=forcing.copy(),
        parameter_schedule=schedule,
        process_standard_normals=process_normals,
        observation_standard_normals=observation_normals,
        initial_states=initial_states,
        initial_covariances=initial_covariances,
        deterministic_truth_states=deterministic_truth,
        truth_process_perturbations=perturbations,
        truth_projection_adjustments=projection_adjustments,
        switch_boundary_projection_adjustments=boundary_adjustments,
        truth_states=truth_states,
        truth_discharge=truth_discharge,
        observations=observations,
        posterior_probabilities=probabilities,
        global_posterior_states=global_states,
    )
