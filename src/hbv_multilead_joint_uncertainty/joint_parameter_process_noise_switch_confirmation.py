"""Joint parameter and process-noise switching during HBV-lite assimilation only.

Both the true parameter candidate and the true lower-groundwater process-noise
level switch at every stage boundary.  The confirmation is judged on two
separately preregistered margins: the parameter margin (posterior summed over
noise levels, clear-dominance rule) and the noise margin (posterior summed over
parameter candidates, top-ranked rule).  The joint unique-combination readout
is descriptive only.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np

from hbv_multilead_joint_uncertainty.methods import MethodCandidate, build_method_bank
from hbv_multilead_joint_uncertainty.state_domain_consistent_parameter_switch_confirmation import (
    build_fixed_lower_groundwater_covariance,
    exact_binomial_interval,
    first_complete_clear_dominance_run,
    validate_parameter_candidates,
)
from hbv_multilead_joint_uncertainty.synthetic_truth import (
    advance_reference_state,
    generate_reference_truth,
    project_reference_state,
    reference_routed_discharge,
)


STATE_COUNT = 15
LOWER_GROUNDWATER_STATE_INDEX = 4


@dataclass(frozen=True)
class JointSwitchConfirmationResult:
    """All arrays needed to audit the joint truth and assimilation independently."""

    block_ids: np.ndarray
    parameter_ids: np.ndarray
    process_ids: np.ndarray
    candidate_parameter_ids: np.ndarray
    candidate_process_ids: np.ndarray
    parameter_vectors: np.ndarray
    process_standard_deviations: np.ndarray
    forcing_blocks: np.ndarray
    parameter_schedule: np.ndarray
    process_schedule: np.ndarray
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
    parameter_margin_probabilities: np.ndarray
    noise_margin_probabilities: np.ndarray
    global_posterior_states: np.ndarray
    observation_standard_deviation: float


def _validated_process_ids(process_standard_deviations: Mapping[str, float]) -> tuple[str, str, str]:
    identifiers = tuple(str(key) for key in process_standard_deviations)
    if len(identifiers) != 3 or len(set(identifiers)) != 3:
        raise ValueError("process contract must contain exactly three unique identifiers")
    values = [float(process_standard_deviations[key]) for key in identifiers]
    if not all(np.isfinite(value) and value > 0.0 for value in values):
        raise ValueError("process standard deviations must be finite and positive")
    if not values[0] < values[1] < values[2]:
        raise ValueError("process standard deviations must be strictly increasing")
    return identifiers  # type: ignore[return-value]


def build_aligned_joint_schedules(
    parameter_orders: Sequence[Sequence[str]],
    process_orders: Sequence[Sequence[str]],
    stage_length_days: int,
) -> tuple[np.ndarray, np.ndarray]:
    """Expand the frozen aligned stage orders into per-day schedules."""
    length = int(stage_length_days)
    if length <= 0:
        raise ValueError("stage_length_days must be a positive integer")
    if len(parameter_orders) != 3 or len(process_orders) != 3:
        raise ValueError("exactly three truth trials are frozen")
    parameter_rows = []
    process_rows = []
    for parameter_order, process_order in zip(parameter_orders, process_orders):
        if len(parameter_order) != 3 or len(set(parameter_order)) != 3:
            raise ValueError("each parameter order must contain three unique stages")
        if len(process_order) != 3 or len(set(process_order)) != 3:
            raise ValueError("each process order must contain three unique stages")
        parameter_rows.append(
            [str(identifier) for identifier in parameter_order for _ in range(length)]
        )
        process_rows.append(
            [str(identifier) for identifier in process_order for _ in range(length)]
        )
    parameter_schedule = np.asarray(parameter_rows, dtype=np.str_)
    process_schedule = np.asarray(process_rows, dtype=np.str_)
    for trial in range(3):
        parameter_changes = {
            day
            for day in range(1, parameter_schedule.shape[1])
            if parameter_schedule[trial, day] != parameter_schedule[trial, day - 1]
        }
        process_changes = {
            day
            for day in range(1, process_schedule.shape[1])
            if process_schedule[trial, day] != process_schedule[trial, day - 1]
        }
        if parameter_changes != process_changes or len(parameter_changes) != 2:
            raise ValueError("parameter and process switches must align at two boundaries")
    return parameter_schedule, process_schedule


def generate_joint_switch_truth(
    forcing,
    parameter_vectors: Mapping[str, Mapping[str, float]],
    initial_state,
    parameter_schedule,
    process_standard_deviations: Mapping[str, float],
    process_schedule,
    lower_groundwater_standard_normals,
) -> dict[str, np.ndarray]:
    """Generate jointly switched truth while rejecting every state projection."""
    identifiers, parameters = validate_parameter_candidates(parameter_vectors)
    process_ids = _validated_process_ids(process_standard_deviations)
    forcing_values = np.asarray(forcing, dtype=np.float64)
    parameter_days = np.asarray(parameter_schedule).astype(str)
    process_days = np.asarray(process_schedule).astype(str)
    normals = np.asarray(lower_groundwater_standard_normals, dtype=np.float64)
    state = np.asarray(initial_state, dtype=np.float64).copy()
    if (
        forcing_values.ndim != 2
        or forcing_values.shape[1] != 3
        or len(forcing_values) == 0
        or not np.all(np.isfinite(forcing_values))
    ):
        raise ValueError("forcing must be one nonempty finite days-by-three array")
    day_count = len(forcing_values)
    if parameter_days.shape != (day_count,) or process_days.shape != (day_count,):
        raise ValueError("both schedules must match forcing days")
    if normals.shape != (day_count,) or not np.all(np.isfinite(normals)):
        raise ValueError("standard normals must match forcing days and be finite")
    if set(parameter_days) - set(identifiers) or set(process_days) - set(process_ids):
        raise ValueError("a schedule contains an unknown identifier")
    if state.shape != (STATE_COUNT,) or not np.all(np.isfinite(state)):
        raise ValueError("initial_state must be one finite fifteen-state vector")

    deterministic = np.empty((day_count, STATE_COUNT), dtype=np.float64)
    perturbations = np.zeros((day_count, STATE_COUNT), dtype=np.float64)
    projection_adjustments = np.empty((day_count, STATE_COUNT), dtype=np.float64)
    boundary_adjustments = np.zeros((day_count, STATE_COUNT), dtype=np.float64)
    states = np.empty((day_count, STATE_COUNT), dtype=np.float64)
    discharge = np.empty(day_count, dtype=np.float64)

    for day, (rain, potential_evaporation, temperature) in enumerate(forcing_values):
        active_parameters = parameters[parameter_days[day]]
        standard_deviation = float(process_standard_deviations[process_days[day]])
        if day > 0 and parameter_days[day] != parameter_days[day - 1]:
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
        perturbation[LOWER_GROUNDWATER_STATE_INDEX] = normals[day] * standard_deviation
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
        discharge[day] = reference_routed_discharge(state, active_parameters["lag_time"])

    return {
        "deterministic_states": deterministic,
        "process_perturbations": perturbations,
        "projection_adjustments": projection_adjustments,
        "switch_boundary_projection_adjustments": boundary_adjustments,
        "states": states,
        "discharge": discharge,
    }


def first_complete_top_ranked_run(
    probabilities,
    true_candidate_index: int,
    consecutive_days: int,
    window_days: int,
    latest_allowed_start_day: int,
) -> int | None:
    """Return the first complete top-ranked run starting no later than allowed."""
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
    latest_start = int(latest_allowed_start_day)
    if (
        index < 0
        or index >= 3
        or run_length <= 0
        or window < run_length
        or len(values) < window
        or latest_start < 0
        or latest_start > window - run_length
    ):
        raise ValueError("top-ranked response thresholds are invalid")
    top = np.argmax(values[:window], axis=1) == index
    for start in range(latest_start + 1):
        if bool(np.all(top[start : start + run_length])):
            return start
    return None


def summarize_joint_switch_response(
    parameter_margin_probabilities,
    noise_margin_probabilities,
    parameter_schedule,
    process_schedule,
    parameter_ids: Sequence[str],
    process_ids: Sequence[str],
    parameter_rule: Mapping[str, float],
    noise_rule: Mapping[str, float],
) -> dict:
    """Evaluate both frozen margin rules for all switch events."""
    parameter_margin = np.asarray(parameter_margin_probabilities, dtype=np.float64)
    noise_margin = np.asarray(noise_margin_probabilities, dtype=np.float64)
    parameter_days = np.asarray(parameter_schedule).astype(str)
    process_days = np.asarray(process_schedule).astype(str)
    parameter_names = tuple(str(value) for value in parameter_ids)
    process_names = tuple(str(value) for value in process_ids)
    block_count, trial_count, day_count, _ = parameter_margin.shape

    events = []
    for block in range(block_count):
        for trial in range(trial_count):
            for day in range(1, day_count):
                if parameter_days[trial, day] == parameter_days[trial, day - 1]:
                    continue
                old_parameter = parameter_names.index(parameter_days[trial, day - 1])
                new_parameter = parameter_names.index(parameter_days[trial, day])
                old_process = process_names.index(process_days[trial, day - 1])
                new_process = process_names.index(process_days[trial, day])
                parameter_start = first_complete_clear_dominance_run(
                    parameter_margin[block, trial, day:],
                    new_parameter,
                    int(parameter_rule["consecutive_clear_dominance_days"]),
                    int(parameter_rule["response_window_days"]),
                    float(parameter_rule["minimum_new_true_candidate_probability_exclusive"]),
                    float(parameter_rule["minimum_probability_margin_over_runner_up_inclusive"]),
                )
                noise_start = first_complete_top_ranked_run(
                    noise_margin[block, trial, day:],
                    new_process,
                    int(noise_rule["consecutive_top_ranked_days"]),
                    int(noise_rule["response_window_days"]),
                    int(noise_rule["latest_allowed_response_start_day"]),
                )
                events.append(
                    {
                        "event_id": (
                            f"block_{block + 1:02d}_trial_{trial + 1}"
                            f"_switch_day_{day + 1}"
                        ),
                        "block_index": block,
                        "trial_index": trial,
                        "switch_day_index": day,
                        "old_parameter_id": parameter_names[old_parameter],
                        "new_parameter_id": parameter_names[new_parameter],
                        "old_process_id": process_names[old_process],
                        "new_process_id": process_names[new_process],
                        "parameter_transition_label": (
                            f"{parameter_names[old_parameter]}_to_"
                            f"{parameter_names[new_parameter]}"
                        ),
                        "noise_transition_label": (
                            f"{process_names[old_process]}_to_"
                            f"{process_names[new_process]}"
                        ),
                        "parameter_numeric_success": parameter_start is not None,
                        "parameter_response_start_day": parameter_start,
                        "noise_numeric_success": noise_start is not None,
                        "noise_response_start_day": noise_start,
                    }
                )

    def directed_summaries(label_key: str, success_key: str, start_key: str, rule):
        grouped: dict[str, list[dict]] = {}
        for event in events:
            grouped.setdefault(event[label_key], []).append(event)
        summaries = []
        for label in sorted(grouped):
            rows = grouped[label]
            successes = sum(1 for row in rows if row[success_key])
            lower, upper = exact_binomial_interval(
                successes, len(rows), float(rule["confidence_level"])
            )
            starts = sorted(
                row[start_key] for row in rows if row[start_key] is not None
            )
            summaries.append(
                {
                    "transition_label": label,
                    "event_count": len(rows),
                    "successful_event_count": successes,
                    "success_fraction": successes / len(rows),
                    "exact_interval_lower": lower,
                    "exact_interval_upper": upper,
                    "criterion_passed": bool(
                        successes
                        >= int(rule["minimum_successful_events_per_directed_transition"])
                        and lower
                        > float(rule["minimum_exact_interval_lower_bound_exclusive"])
                    ),
                    "median_response_start_day": (
                        float(np.median(starts)) if starts else None
                    ),
                    "maximum_response_start_day": max(starts) if starts else None,
                }
            )
        return summaries

    return {
        "events": events,
        "parameter_margin_summaries": directed_summaries(
            "parameter_transition_label",
            "parameter_numeric_success",
            "parameter_response_start_day",
            parameter_rule,
        ),
        "noise_margin_summaries": directed_summaries(
            "noise_transition_label",
            "noise_numeric_success",
            "noise_response_start_day",
            noise_rule,
        ),
    }


def summarize_joint_descriptive_readouts(
    posterior_probabilities,
    parameter_margin_probabilities,
    noise_margin_probabilities,
    parameter_schedule,
    process_schedule,
    parameter_ids: Sequence[str],
    process_ids: Sequence[str],
    candidate_parameter_ids: Sequence[str],
    candidate_process_ids: Sequence[str],
    stage_length_days: int,
) -> dict:
    """Describe full-stage margin accuracy and joint unique-combination behaviour."""
    posterior = np.asarray(posterior_probabilities, dtype=np.float64)
    parameter_margin = np.asarray(parameter_margin_probabilities, dtype=np.float64)
    noise_margin = np.asarray(noise_margin_probabilities, dtype=np.float64)
    parameter_days = np.asarray(parameter_schedule).astype(str)
    process_days = np.asarray(process_schedule).astype(str)
    parameter_names = tuple(str(value) for value in parameter_ids)
    process_names = tuple(str(value) for value in process_ids)
    candidate_pairs = tuple(
        (str(parameter), str(process))
        for parameter, process in zip(candidate_parameter_ids, candidate_process_ids)
    )
    block_count, trial_count, day_count, _ = posterior.shape
    length = int(stage_length_days)

    parameter_rows: dict[str, dict[str, float]] = {}
    noise_rows: dict[str, dict[str, float]] = {}
    joint_rows: dict[str, dict[str, float]] = {}
    for block in range(block_count):
        for trial in range(trial_count):
            for start in range(0, day_count, length):
                true_parameter = parameter_days[trial, start]
                true_process = process_days[trial, start]
                parameter_index = parameter_names.index(true_parameter)
                process_index = process_names.index(true_process)
                joint_index = candidate_pairs.index((true_parameter, true_process))
                stop = start + length
                parameter_slice = parameter_margin[block, trial, start:stop]
                noise_slice = noise_margin[block, trial, start:stop]
                joint_slice = posterior[block, trial, start:stop]
                for rows, key, index, values in (
                    (parameter_rows, true_parameter, parameter_index, parameter_slice),
                    (noise_rows, true_process, process_index, noise_slice),
                    (joint_rows, f"{true_parameter}__{true_process}", joint_index, joint_slice),
                ):
                    entry = rows.setdefault(
                        key,
                        {"day_count": 0, "top_ranked_day_count": 0, "probability_sum": 0.0},
                    )
                    entry["day_count"] += values.shape[0]
                    entry["top_ranked_day_count"] += int(
                        np.count_nonzero(np.argmax(values, axis=1) == index)
                    )
                    entry["probability_sum"] += float(values[:, index].sum())

    def finalize(rows: dict[str, dict[str, float]]) -> list[dict]:
        output = []
        for key in sorted(rows):
            entry = rows[key]
            output.append(
                {
                    "true_identifier": key,
                    "day_count": int(entry["day_count"]),
                    "top_ranked_fraction": entry["top_ranked_day_count"] / entry["day_count"],
                    "mean_true_probability": entry["probability_sum"] / entry["day_count"],
                }
            )
        return output

    return {
        "parameter_margin_full_stage": finalize(parameter_rows),
        "noise_margin_full_stage": finalize(noise_rows),
        "joint_unique_combination_full_stage": finalize(joint_rows),
    }


def run_joint_switch_confirmation(
    forcing_blocks,
    block_ids: Sequence[str],
    parameter_vectors: Mapping[str, Mapping[str, float]],
    process_standard_deviations: Mapping[str, float],
    parameter_orders: Sequence[Sequence[str]],
    process_orders: Sequence[Sequence[str]],
    process_noise_seeds: Sequence[int],
    observation_noise_seeds: Sequence[int],
    warmup_days: int,
    stage_length_days: int,
    initial_covariance_fraction: float,
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
) -> JointSwitchConfirmationResult:
    """Generate jointly switched truths and assimilate them without forecasting."""
    identifiers, parameters = validate_parameter_candidates(parameter_vectors)
    process_ids = _validated_process_ids(process_standard_deviations)
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
    if not np.isfinite(observation_std) or observation_std <= 0.0:
        raise ValueError("observation standard deviation must be finite and positive")

    standard_deviations = {
        identifier: float(process_standard_deviations[identifier])
        for identifier in process_ids
    }
    candidates = tuple(
        MethodCandidate(
            candidate_id=f"{parameter_id}__{process_id}",
            parameter_id=parameter_id,
            process_id=process_id,
            process_scale=standard_deviations[process_id] ** 2,
            parameters=parameters[parameter_id].copy(),
            process_covariance=build_fixed_lower_groundwater_covariance(
                standard_deviations[process_id]
            ),
        )
        for parameter_id in identifiers
        for process_id in process_ids
    )
    candidate_parameter_ids = tuple(candidate.parameter_id for candidate in candidates)
    candidate_process_ids = tuple(candidate.process_id for candidate in candidates)
    parameter_schedule, process_schedule = build_aligned_joint_schedules(
        parameter_orders, process_orders, stage_length
    )

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
        (block_count, 3, assimilation_days, len(candidates)), dtype=np.float64
    )
    global_states = np.empty(truth_shape, dtype=np.float64)

    reference_parameters = parameters[identifiers[1]]
    fraction = float(initial_covariance_fraction)
    if not np.isfinite(fraction) or fraction <= 0.0:
        raise ValueError("initial covariance fraction must be finite and positive")
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
        scales = np.maximum(np.abs(initial_state), 1.0)
        initial_covariance = np.diag(np.square(fraction * scales))
        initial_covariances[block] = initial_covariance
        active_forcing = forcing[block, warmup:]

        for trial in range(3):
            truth = generate_joint_switch_truth(
                active_forcing,
                parameters,
                initial_state,
                parameter_schedule[trial],
                standard_deviations,
                process_schedule[trial],
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

            bank = build_method_bank(
                candidates=candidates,
                initial_states={identifier: initial_state for identifier in identifiers},
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

    parameter_margin = np.empty(
        (block_count, 3, assimilation_days, 3), dtype=np.float64
    )
    noise_margin = np.empty_like(parameter_margin)
    for index, identifier in enumerate(identifiers):
        member = [
            column
            for column, parameter_id in enumerate(candidate_parameter_ids)
            if parameter_id == identifier
        ]
        parameter_margin[..., index] = probabilities[..., member].sum(axis=-1)
    for index, identifier in enumerate(process_ids):
        member = [
            column
            for column, process_id in enumerate(candidate_process_ids)
            if process_id == identifier
        ]
        noise_margin[..., index] = probabilities[..., member].sum(axis=-1)

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
        parameter_margin,
        noise_margin,
        global_states,
    )
    if not all(np.all(np.isfinite(values)) for values in arrays):
        raise FloatingPointError("experiment produced a non-finite array")
    if np.any(projection_adjustments != 0.0):
        raise ValueError("truth transition projection gate failed")
    if np.any(boundary_adjustments != 0.0):
        raise ValueError("switch-boundary projection gate failed")
    for margins in (probabilities, parameter_margin, noise_margin):
        if not np.allclose(margins.sum(axis=-1), 1.0, rtol=0.0, atol=1e-12):
            raise FloatingPointError("posterior probabilities are not normalized")

    return JointSwitchConfirmationResult(
        block_ids=np.asarray(block_labels, dtype=np.str_),
        parameter_ids=np.asarray(identifiers, dtype=np.str_),
        process_ids=np.asarray(process_ids, dtype=np.str_),
        candidate_parameter_ids=np.asarray(candidate_parameter_ids, dtype=np.str_),
        candidate_process_ids=np.asarray(candidate_process_ids, dtype=np.str_),
        parameter_vectors=np.asarray(
            [
                [parameters[identifier][name] for name in sorted(parameters[identifier])]
                for identifier in identifiers
            ],
            dtype=np.float64,
        ),
        process_standard_deviations=np.asarray(
            [standard_deviations[identifier] for identifier in process_ids],
            dtype=np.float64,
        ),
        forcing_blocks=forcing.copy(),
        parameter_schedule=parameter_schedule,
        process_schedule=process_schedule,
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
        parameter_margin_probabilities=parameter_margin,
        noise_margin_probabilities=noise_margin,
        global_posterior_states=global_states,
        observation_standard_deviation=observation_std,
    )
