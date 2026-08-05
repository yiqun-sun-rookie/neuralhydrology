"""Clean synthetic process-noise switching during HBV-lite assimilation only."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np
from scipy.stats import beta as beta_distribution

from hbv_multilead_joint_uncertainty.methods import (
    build_method_bank,
    build_method_definitions,
)
from hbv_multilead_joint_uncertainty.synthetic_truth import (
    PARAMETER_NAMES,
    advance_reference_state,
    generate_reference_truth,
    project_reference_state,
    reference_routed_discharge,
)


STATE_COUNT = 15
LOWER_GROUNDWATER_STATE_INDEX = 4


@dataclass(frozen=True)
class StateDomainConsistentProcessNoiseSwitchResult:
    """All arrays needed to audit the truth and assimilation independently."""

    block_ids: np.ndarray
    process_ids: np.ndarray
    forcing_blocks: np.ndarray
    process_schedule: np.ndarray
    process_standard_normals: np.ndarray
    observation_standard_normals: np.ndarray
    initial_states: np.ndarray
    initial_covariances: np.ndarray
    deterministic_truth_states: np.ndarray
    truth_process_perturbations: np.ndarray
    truth_projection_adjustments: np.ndarray
    truth_states: np.ndarray
    truth_discharge: np.ndarray
    observations: np.ndarray
    posterior_probabilities: np.ndarray
    global_posterior_states: np.ndarray


def _validated_process_ids(process_ids: Sequence[str]) -> tuple[str, str, str]:
    identifiers = tuple(str(value) for value in process_ids)
    if len(identifiers) != 3 or len(set(identifiers)) != 3:
        raise ValueError("process_ids must contain exactly three unique identifiers")
    return identifiers


def build_rotating_process_schedule(
    process_ids: Sequence[str],
    stage_length_days: int,
) -> np.ndarray:
    """Build three balanced cyclic truth schedules."""
    identifiers = _validated_process_ids(process_ids)
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
        [
            [identifier for identifier in order for _ in range(length)]
            for order in orders
        ],
        dtype=np.str_,
    )


def build_lower_groundwater_process_covariances(
    standard_deviations: Mapping[str, float],
) -> dict[str, np.ndarray]:
    """Create three covariances supported only on lower groundwater storage."""
    if len(standard_deviations) != 3:
        raise ValueError("standard_deviations must contain exactly three candidates")
    result: dict[str, np.ndarray] = {}
    for raw_identifier, raw_standard_deviation in standard_deviations.items():
        identifier = str(raw_identifier)
        standard_deviation = float(raw_standard_deviation)
        if (
            not identifier
            or identifier in result
            or not np.isfinite(standard_deviation)
            or standard_deviation <= 0.0
        ):
            raise ValueError(
                "process identifiers must be unique and standard deviations positive"
            )
        covariance = np.zeros((STATE_COUNT, STATE_COUNT), dtype=np.float64)
        covariance[
            LOWER_GROUNDWATER_STATE_INDEX, LOWER_GROUNDWATER_STATE_INDEX
        ] = standard_deviation**2
        result[identifier] = covariance
    return result


def _validated_parameters(parameters: Mapping[str, float]) -> dict[str, float]:
    if set(parameters) != set(PARAMETER_NAMES):
        raise ValueError("parameters must contain exactly thirteen HBV-lite values")
    result = {name: float(parameters[name]) for name in PARAMETER_NAMES}
    if not np.all(np.isfinite(tuple(result.values()))):
        raise ValueError("parameters must be finite")
    return result


def generate_state_domain_consistent_truth(
    forcing,
    parameters: Mapping[str, float],
    initial_state,
    process_schedule,
    process_standard_deviations: Mapping[str, float],
    lower_groundwater_standard_normals,
) -> dict[str, np.ndarray]:
    """Generate one continuous truth and reject every post-noise projection."""
    forcing_values = np.asarray(forcing, dtype=np.float64)
    schedule = np.asarray(process_schedule).astype(str)
    normals = np.asarray(lower_groundwater_standard_normals, dtype=np.float64)
    state = np.asarray(initial_state, dtype=np.float64).copy()
    parameter_values = _validated_parameters(parameters)
    standard_deviations = {
        str(identifier): float(value)
        for identifier, value in process_standard_deviations.items()
    }
    if (
        forcing_values.ndim != 2
        or forcing_values.shape[1] != 3
        or len(forcing_values) == 0
        or not np.all(np.isfinite(forcing_values))
    ):
        raise ValueError("forcing must be one nonempty finite days-by-three array")
    day_count = len(forcing_values)
    if schedule.shape != (day_count,) or normals.shape != (day_count,):
        raise ValueError("process schedule and normals must match forcing days")
    if state.shape != (STATE_COUNT,) or not np.all(np.isfinite(state)):
        raise ValueError("initial_state must be one finite fifteen-state vector")
    if set(schedule) - set(standard_deviations):
        raise ValueError("process schedule contains an unknown process identifier")
    if (
        not np.all(np.isfinite(tuple(standard_deviations.values())))
        or any(value <= 0.0 for value in standard_deviations.values())
        or not np.all(np.isfinite(normals))
    ):
        raise ValueError("process standard deviations and normals must be finite")

    deterministic = np.empty((day_count, STATE_COUNT), dtype=np.float64)
    perturbations = np.zeros((day_count, STATE_COUNT), dtype=np.float64)
    adjustments = np.empty((day_count, STATE_COUNT), dtype=np.float64)
    states = np.empty((day_count, STATE_COUNT), dtype=np.float64)
    discharge = np.empty(day_count, dtype=np.float64)

    for day, (rain, potential_evaporation, temperature) in enumerate(
        forcing_values
    ):
        deterministic_state = advance_reference_state(
            state,
            float(rain),
            float(potential_evaporation),
            float(temperature),
            parameter_values,
        )
        perturbation = np.zeros(STATE_COUNT, dtype=np.float64)
        perturbation[LOWER_GROUNDWATER_STATE_INDEX] = (
            normals[day] * standard_deviations[schedule[day]]
        )
        unprojected_state = deterministic_state + perturbation
        projected_state = project_reference_state(
            unprojected_state, parameter_values
        )
        adjustment = projected_state - unprojected_state

        deterministic[day] = deterministic_state
        perturbations[day] = perturbation
        adjustments[day] = adjustment
        if np.any(adjustment != 0.0):
            raise ValueError(
                "truth state-domain gate failed: a process-noise realization "
                "would require projection"
            )
        state = unprojected_state
        states[day] = state
        discharge[day] = reference_routed_discharge(
            state, parameter_values["lag_time"]
        )

    return {
        "deterministic_states": deterministic,
        "process_perturbations": perturbations,
        "projection_adjustments": adjustments,
        "states": states,
        "discharge": discharge,
    }


def first_complete_top_ranked_run(
    top_ranked: np.ndarray,
    consecutive_days: int,
    window_days: int,
) -> int | None:
    """Return the first complete run start within the frozen response window."""
    values = np.asarray(top_ranked, dtype=bool)
    if values.ndim != 1:
        raise ValueError("top_ranked must be one-dimensional")
    if (
        isinstance(consecutive_days, bool)
        or isinstance(window_days, bool)
        or not isinstance(consecutive_days, (int, np.integer))
        or not isinstance(window_days, (int, np.integer))
        or int(consecutive_days) <= 0
        or int(window_days) < int(consecutive_days)
        or len(values) < int(window_days)
    ):
        raise ValueError("response run and window lengths are inconsistent")
    run_length = int(consecutive_days)
    window = int(window_days)
    for start in range(window - run_length + 1):
        if bool(np.all(values[start : start + run_length])):
            return start
    return None


def exact_binomial_interval(
    successes: int,
    total: int,
    confidence_level: float = 0.95,
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
    process_ids: Sequence[str],
) -> tuple[tuple[str, str], ...]:
    identifiers = _validated_process_ids(process_ids)
    return (
        (identifiers[0], identifiers[1]),
        (identifiers[1], identifiers[2]),
        (identifiers[2], identifiers[0]),
    )


def summarize_switch_response(
    probabilities: np.ndarray,
    process_schedule: np.ndarray,
    process_ids: Sequence[str],
    response_window_days: int,
    consecutive_top_days: int,
    minimum_successful_events: int,
    minimum_interval_lower_bound: float,
) -> tuple[list[dict], list[dict]]:
    """Score the prospectively frozen post-switch top-rank response."""
    identifiers = _validated_process_ids(process_ids)
    values = np.asarray(probabilities, dtype=np.float64)
    schedule = np.asarray(process_schedule).astype(str)
    if values.ndim != 4 or values.shape[-1] != 3:
        raise ValueError(
            "probabilities must have block, truth-trial, day, candidate dimensions"
        )
    block_count, trial_count, day_count, _ = values.shape
    if schedule.shape != (trial_count, day_count):
        raise ValueError("process schedule shape must match truth trials and days")
    if (
        not np.all(np.isfinite(values))
        or np.any(values < 0.0)
        or not np.allclose(values.sum(axis=-1), 1.0, rtol=0.0, atol=1e-12)
    ):
        raise ValueError("probabilities must be finite, nonnegative, and normalized")
    window = int(response_window_days)
    consecutive = int(consecutive_top_days)
    minimum = int(minimum_successful_events)
    lower_bound = float(minimum_interval_lower_bound)
    if (
        window <= 0
        or consecutive <= 0
        or consecutive > window
        or minimum <= 0
        or not np.isfinite(lower_bound)
        or lower_bound < 0.0
        or lower_bound >= 1.0
    ):
        raise ValueError("response thresholds are invalid")
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
                old_identifier = schedule[trial, boundary - 1]
                new_identifier = schedule[trial, boundary]
                if (
                    old_identifier not in candidate_index
                    or new_identifier not in candidate_index
                ):
                    raise ValueError("schedule contains an unknown process identifier")
                top_ranked = (
                    np.argmax(
                        values[block, trial, boundary : boundary + window],
                        axis=-1,
                    )
                    == candidate_index[new_identifier]
                )
                response_start = first_complete_top_ranked_run(
                    top_ranked,
                    consecutive_days=consecutive,
                    window_days=window,
                )
                events.append(
                    {
                        "event_id": (
                            f"block_{block + 1:02d}_trial_{trial + 1}_"
                            f"switch_day_{boundary + 1}"
                        ),
                        "block_index": block,
                        "trial_index": trial,
                        "switch_day_index": int(boundary),
                        "switch_day_number": int(boundary + 1),
                        "old_process_id": str(old_identifier),
                        "new_process_id": str(new_identifier),
                        "transition_label": (
                            f"{old_identifier}_to_{new_identifier}"
                        ),
                        "success": response_start is not None,
                        "response_start_day": (
                            None if response_start is None else int(response_start)
                        ),
                        "new_candidate_top_ranked_days_in_window": int(
                            np.count_nonzero(top_ranked)
                        ),
                    }
                )

    summaries: list[dict] = []
    for old_identifier, new_identifier in _directed_transition_order(identifiers):
        selected = [
            row
            for row in events
            if row["old_process_id"] == old_identifier
            and row["new_process_id"] == new_identifier
        ]
        successes = sum(bool(row["success"]) for row in selected)
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
                "old_process_id": old_identifier,
                "new_process_id": new_identifier,
                "transition_label": f"{old_identifier}_to_{new_identifier}",
                "event_count": event_count,
                "successful_event_count": successes,
                "response_fraction": successes / event_count,
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
                "criterion_passed": (
                    successes >= minimum and lower > lower_bound
                ),
            }
        )
    return events, summaries


def build_probability_response_curves(
    probabilities: np.ndarray,
    process_schedule: np.ndarray,
    process_ids: Sequence[str],
    pre_switch_days: int = 15,
    post_switch_days: int = 30,
) -> list[dict]:
    """Aggregate matched probability traces around each directed switch."""
    identifiers = _validated_process_ids(process_ids)
    values = np.asarray(probabilities, dtype=np.float64)
    schedule = np.asarray(process_schedule).astype(str)
    if values.ndim != 4 or values.shape[-1] != 3:
        raise ValueError("probabilities have an invalid shape")
    if schedule.shape != values.shape[1:3]:
        raise ValueError("process schedule shape does not match probabilities")
    before = int(pre_switch_days)
    after = int(post_switch_days)
    if before < 0 or after <= 0:
        raise ValueError("response curve window is invalid")
    rows: list[dict] = []
    for old_identifier, new_identifier in _directed_transition_order(identifiers):
        traces = []
        for block in range(values.shape[0]):
            for trial in range(values.shape[1]):
                boundaries = np.flatnonzero(
                    schedule[trial, 1:] != schedule[trial, :-1]
                ) + 1
                for boundary in boundaries:
                    if (
                        schedule[trial, boundary - 1] == old_identifier
                        and schedule[trial, boundary] == new_identifier
                    ):
                        if boundary - before < 0 or boundary + after > values.shape[2]:
                            raise ValueError(
                                "probability response curve exceeds saved days"
                            )
                        traces.append(
                            values[
                                block,
                                trial,
                                boundary - before : boundary + after,
                            ]
                        )
        trace_values = np.asarray(traces, dtype=np.float64)
        if trace_values.shape != (16, before + after, 3):
            raise ValueError(
                "each directed transition must contain sixteen matched traces"
            )
        for offset, relative_day in enumerate(range(-before, after)):
            for candidate, candidate_id in enumerate(identifiers):
                candidate_values = trace_values[:, offset, candidate]
                rows.append(
                    {
                        "transition_label": (
                            f"{old_identifier}_to_{new_identifier}"
                        ),
                        "old_process_id": old_identifier,
                        "new_process_id": new_identifier,
                        "relative_day": relative_day,
                        "candidate_process_id": candidate_id,
                        "probability_p10": float(
                            np.quantile(candidate_values, 0.10)
                        ),
                        "probability_median": float(
                            np.median(candidate_values)
                        ),
                        "probability_p90": float(
                            np.quantile(candidate_values, 0.90)
                        ),
                    }
                )
    return rows


def summarize_full_stage_accuracy(
    probabilities: np.ndarray,
    process_schedule: np.ndarray,
    process_ids: Sequence[str],
) -> list[dict]:
    """Return descriptive all-day top-rank accuracy for each true noise level."""
    identifiers = _validated_process_ids(process_ids)
    values = np.asarray(probabilities, dtype=np.float64)
    schedule = np.asarray(process_schedule).astype(str)
    if values.ndim != 4 or schedule.shape != values.shape[1:3]:
        raise ValueError("stage-accuracy inputs have incompatible shapes")
    candidate_index = {
        identifier: index for index, identifier in enumerate(identifiers)
    }
    rows = []
    top = np.argmax(values, axis=-1)
    for identifier in identifiers:
        trial_day_mask = schedule == identifier
        mask = np.broadcast_to(trial_day_mask, values.shape[:3])
        true_index = candidate_index[identifier]
        count = int(np.count_nonzero(mask))
        rows.append(
            {
                "true_process_id": identifier,
                "day_count": count,
                "top_ranked_day_count": int(
                    np.count_nonzero((top == true_index) & mask)
                ),
                "top_ranked_fraction": float(
                    np.mean(top[mask] == true_index)
                ),
                "mean_true_candidate_probability": float(
                    np.mean(values[..., true_index][mask])
                ),
            }
        )
    return rows


def _initial_covariance(
    initial_state: np.ndarray,
    covariance_fraction: float,
) -> np.ndarray:
    fraction = float(covariance_fraction)
    if not np.isfinite(fraction) or fraction <= 0.0:
        raise ValueError("initial covariance fraction must be positive")
    scales = np.maximum(np.abs(initial_state), 1.0)
    return np.diag(np.square(fraction * scales))


def run_state_domain_consistent_process_noise_switch(
    forcing_blocks,
    block_ids: Sequence[str],
    parameter_vectors: Mapping[str, Mapping[str, float]],
    process_standard_deviations: Mapping[str, float],
    process_noise_seeds: Sequence[int],
    observation_noise_seeds: Sequence[int],
    warmup_days: int,
    stage_length_days: int,
    initial_covariance_fraction: float,
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
) -> StateDomainConsistentProcessNoiseSwitchResult:
    """Generate clean switched truths and assimilate them without forecasting."""
    forcing = np.asarray(forcing_blocks, dtype=np.float64)
    identifiers = _validated_process_ids(process_standard_deviations)
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
    if "trained_center" not in parameter_vectors:
        raise ValueError("parameter vectors must include trained_center")
    truth_parameters = _validated_parameters(parameter_vectors["trained_center"])
    observation_standard_deviation = float(observation_standard_deviation)
    if (
        not np.isfinite(observation_standard_deviation)
        or observation_standard_deviation <= 0.0
    ):
        raise ValueError("observation standard deviation must be positive")

    standard_deviations = {
        identifier: float(process_standard_deviations[identifier])
        for identifier in identifiers
    }
    process_covariances = build_lower_groundwater_process_covariances(
        standard_deviations
    )
    process_scales = {
        identifier: standard_deviations[identifier] ** 2
        for identifier in identifiers
    }
    definitions = build_method_definitions(
        parameter_vectors=parameter_vectors,
        process_scales=process_scales,
        process_covariances=process_covariances,
        selected_process_id=identifiers[1],
    )
    noise_candidates = definitions["noise_only"]
    if tuple(candidate.process_id for candidate in noise_candidates) != identifiers:
        raise ValueError("noise candidate order changed unexpectedly")

    schedule = build_rotating_process_schedule(identifiers, stage_length)
    process_normals = np.empty(
        (block_count, assimilation_days), dtype=np.float64
    )
    observation_normals = np.empty_like(process_normals)
    initial_states = np.empty((block_count, STATE_COUNT), dtype=np.float64)
    initial_covariances = np.empty(
        (block_count, STATE_COUNT, STATE_COUNT), dtype=np.float64
    )
    truth_shape = (block_count, 3, assimilation_days, STATE_COUNT)
    deterministic_truth = np.empty(truth_shape, dtype=np.float64)
    perturbations = np.empty(truth_shape, dtype=np.float64)
    projection_adjustments = np.empty(truth_shape, dtype=np.float64)
    truth_states = np.empty(truth_shape, dtype=np.float64)
    truth_discharge = np.empty(
        (block_count, 3, assimilation_days), dtype=np.float64
    )
    observations = np.empty_like(truth_discharge)
    probabilities = np.empty(
        (block_count, 3, assimilation_days, 3), dtype=np.float64
    )
    global_states = np.empty(truth_shape, dtype=np.float64)

    for block in range(block_count):
        process_normals[block] = np.random.default_rng(
            process_seeds[block]
        ).standard_normal(assimilation_days)
        observation_normals[block] = np.random.default_rng(
            observation_seeds[block]
        ).standard_normal(assimilation_days)
        warmup_truth = generate_reference_truth(
            forcing[block, :warmup], truth_parameters
        )
        initial_state = warmup_truth.states[-1].copy()
        covariance = _initial_covariance(
            initial_state, initial_covariance_fraction
        )
        initial_states[block] = initial_state
        initial_covariances[block] = covariance
        active_forcing = forcing[block, warmup:]

        for trial in range(3):
            truth = generate_state_domain_consistent_truth(
                active_forcing,
                truth_parameters,
                initial_state,
                schedule[trial],
                standard_deviations,
                process_normals[block],
            )
            deterministic_truth[block, trial] = truth[
                "deterministic_states"
            ]
            perturbations[block, trial] = truth["process_perturbations"]
            projection_adjustments[block, trial] = truth[
                "projection_adjustments"
            ]
            truth_states[block, trial] = truth["states"]
            truth_discharge[block, trial] = truth["discharge"]
            observations[block, trial] = (
                truth["discharge"]
                + observation_standard_deviation
                * observation_normals[block]
            )

            bank = build_method_bank(
                candidates=noise_candidates,
                initial_states={"trained_center": initial_state},
                initial_covariance=covariance,
                observation_standard_deviation=observation_standard_deviation,
                factor_transition_stay_probability=(
                    factor_transition_stay_probability
                ),
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
                probabilities[block, trial, day] = (
                    step.posterior_probabilities
                )
                global_states[block, trial, day] = (
                    step.global_posterior_state
                )

    arrays = (
        forcing,
        process_normals,
        observation_normals,
        initial_states,
        initial_covariances,
        deterministic_truth,
        perturbations,
        projection_adjustments,
        truth_states,
        truth_discharge,
        observations,
        probabilities,
        global_states,
    )
    if not all(np.all(np.isfinite(values)) for values in arrays):
        raise FloatingPointError("experiment produced a non-finite array")
    if np.any(projection_adjustments != 0.0):
        raise ValueError("truth state-domain gate failed")
    if not np.allclose(
        probabilities.sum(axis=-1), 1.0, rtol=0.0, atol=1e-12
    ):
        raise FloatingPointError("posterior probabilities are not normalized")

    return StateDomainConsistentProcessNoiseSwitchResult(
        block_ids=np.asarray(block_labels, dtype=np.str_),
        process_ids=np.asarray(identifiers, dtype=np.str_),
        forcing_blocks=forcing.copy(),
        process_schedule=schedule,
        process_standard_normals=process_normals,
        observation_standard_normals=observation_normals,
        initial_states=initial_states,
        initial_covariances=initial_covariances,
        deterministic_truth_states=deterministic_truth,
        truth_process_perturbations=perturbations,
        truth_projection_adjustments=projection_adjustments,
        truth_states=truth_states,
        truth_discharge=truth_discharge,
        observations=observations,
        posterior_probabilities=probabilities,
        global_posterior_states=global_states,
    )
