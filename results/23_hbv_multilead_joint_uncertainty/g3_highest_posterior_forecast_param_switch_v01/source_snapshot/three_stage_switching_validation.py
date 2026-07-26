"""Closed-truth three-stage parameter and process-noise switching validation."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np

from hbv_joint_uncertainty.hbv_adapter import simulate_adapter

from .forecast import forecast_from_posterior
from .methods import MethodCandidate, build_method_bank, build_method_definitions
from .synthetic_truth import (
    advance_reference_state,
    generate_reference_truth,
    project_reference_state,
    reference_routed_discharge,
)


SUPPORTED_SCENARIOS = (
    "parameter_switch",
    "process_noise_switch",
    "parameter_process_noise_switch",
)
METHOD_NAMES = ("open_loop", "fixed_filter", "parameter_only", "noise_only", "joint")


@dataclass(frozen=True)
class ThreeStageTruthSchedule:
    """Exact candidate labels for assimilation and the following forecast period."""

    scenario: str
    primary_method_name: str
    joint_candidate_indices: np.ndarray
    parameter_indices: np.ndarray
    process_indices: np.ndarray
    primary_candidate_indices: np.ndarray
    origin_joint_candidate_indices: np.ndarray
    stage_start_days: np.ndarray
    stage_end_days: np.ndarray


@dataclass(frozen=True)
class ThreeStageSwitchingValidationResult:
    """Raw evidence from one isolated factor-switching validation scenario."""

    scenario: str
    schedule: ThreeStageTruthSchedule
    block_ids: tuple[str, ...]
    process_noise_seeds: np.ndarray
    observation_noise_seeds: np.ndarray
    forcing_blocks: np.ndarray
    warmup_days: int
    stage_lengths: np.ndarray
    assimilation_days: int
    forecast_lead_days: np.ndarray
    method_names: tuple[str, ...]
    method_candidate_ids: tuple[tuple[str, ...], ...]
    method_candidate_counts: np.ndarray
    parameter_ids: tuple[str, str, str]
    process_ids: tuple[str, str, str]
    initial_parameter_states: np.ndarray
    initial_covariances: np.ndarray
    process_standard_normals: np.ndarray
    observation_standard_normals: np.ndarray
    truth_deterministic_states: np.ndarray
    truth_process_perturbations: np.ndarray
    truth_projection_adjustments: np.ndarray
    truth_states: np.ndarray
    truth_discharge: np.ndarray
    observed_discharge: np.ndarray
    truth_forecast_discharge: np.ndarray
    method_assimilation_probabilities: np.ndarray
    method_assimilation_states: np.ndarray
    method_origin_states: np.ndarray
    method_predictions: np.ndarray
    method_candidate_predictions: np.ndarray
    method_forecast_probabilities: np.ndarray
    method_absolute_errors: np.ndarray


def _validated_factor_grid(
    definitions: Mapping[str, Sequence[MethodCandidate]],
) -> tuple[
    tuple[MethodCandidate, ...],
    tuple[str, ...],
    tuple[str, ...],
    dict[tuple[str, str], int],
]:
    if "joint" not in definitions:
        raise ValueError("definitions must contain a joint candidate bank")
    joint = tuple(definitions["joint"])
    parameter_ids = tuple(dict.fromkeys(candidate.parameter_id for candidate in joint))
    process_ids = tuple(dict.fromkeys(candidate.process_id for candidate in joint))
    if len(parameter_ids) != 3 or len(process_ids) != 3 or len(joint) != 9:
        raise ValueError("joint candidates must form a complete three by three grid")
    lookup = {
        (candidate.parameter_id, candidate.process_id): index
        for index, candidate in enumerate(joint)
    }
    expected = {
        (parameter_id, process_id)
        for parameter_id in parameter_ids
        for process_id in process_ids
    }
    if len(lookup) != len(joint) or set(lookup) != expected:
        raise ValueError("joint candidates must form a complete three by three grid")
    if "trained_center" not in parameter_ids:
        raise ValueError("joint candidates must contain the trained-center parameter vector")
    return joint, parameter_ids, process_ids, lookup


def build_three_stage_truth_schedule(
    definitions: Mapping[str, Sequence[MethodCandidate]],
    scenario: str,
    selected_process_id: str,
    stage_lengths: Sequence[int],
    forecast_days: int,
) -> ThreeStageTruthSchedule:
    """Build exact candidate-present truth labels for one three-stage scenario."""

    if scenario not in SUPPORTED_SCENARIOS:
        raise ValueError(f"scenario must be one of {SUPPORTED_SCENARIOS}")
    lengths = tuple(int(value) for value in stage_lengths)
    if len(lengths) != 3:
        raise ValueError("stage_lengths must contain exactly three stages")
    if any(value <= 0 for value in lengths):
        raise ValueError("all three stage lengths must be positive")
    if int(forecast_days) != forecast_days or int(forecast_days) <= 0:
        raise ValueError("forecast_days must be a positive integer")
    forecast_days = int(forecast_days)

    joint, parameter_ids, process_ids, lookup = _validated_factor_grid(definitions)
    if selected_process_id not in process_ids:
        raise ValueError("selected_process_id is outside the process candidate grid")

    parameter_index = {identifier: index for index, identifier in enumerate(parameter_ids)}
    process_index = {identifier: index for index, identifier in enumerate(process_ids)}
    center_parameter_id = "trained_center"
    assimilation_days = int(sum(lengths))
    total_days = assimilation_days + forecast_days
    stage_end_days = np.cumsum(np.asarray(lengths, dtype=np.int64))
    stage_start_days = np.concatenate(
        (np.asarray([0], dtype=np.int64), stage_end_days[:-1])
    )

    if scenario == "parameter_switch":
        primary_method_name = "parameter_only"
        origin_pairs = [
            (parameter_id, selected_process_id) for parameter_id in parameter_ids
        ]
        stage_pairs = [
            [
                (parameter_ids[(origin_index - 2) % 3], selected_process_id),
                (parameter_ids[(origin_index - 1) % 3], selected_process_id),
                (parameter_ids[origin_index], selected_process_id),
            ]
            for origin_index in range(3)
        ]
    elif scenario == "process_noise_switch":
        primary_method_name = "noise_only"
        origin_pairs = [
            (center_parameter_id, process_id) for process_id in process_ids
        ]
        stage_pairs = [
            [
                (center_parameter_id, process_ids[(origin_index - 2) % 3]),
                (center_parameter_id, process_ids[(origin_index - 1) % 3]),
                (center_parameter_id, process_ids[origin_index]),
            ]
            for origin_index in range(3)
        ]
    else:
        primary_method_name = "joint"
        origin_pairs = [
            (candidate.parameter_id, candidate.process_id) for candidate in joint
        ]
        stage_pairs = []
        for origin_index in range(9):
            indices = ((origin_index - 8) % 9, (origin_index - 4) % 9, origin_index)
            stage_pairs.append(
                [(joint[index].parameter_id, joint[index].process_id) for index in indices]
            )

    joint_candidate_indices = np.empty((len(stage_pairs), total_days), dtype=np.int64)
    for truth_index, pairs in enumerate(stage_pairs):
        for stage_index, pair in enumerate(pairs):
            joint_candidate_indices[
                truth_index, stage_start_days[stage_index] : stage_end_days[stage_index]
            ] = lookup[pair]
        joint_candidate_indices[truth_index, assimilation_days:] = lookup[pairs[-1]]

    joint_parameter_indices = np.asarray(
        [parameter_index[candidate.parameter_id] for candidate in joint], dtype=np.int64
    )
    joint_process_indices = np.asarray(
        [process_index[candidate.process_id] for candidate in joint], dtype=np.int64
    )
    parameter_indices = joint_parameter_indices[joint_candidate_indices]
    process_indices = joint_process_indices[joint_candidate_indices]
    if scenario == "parameter_switch":
        primary_candidate_indices = parameter_indices.copy()
    elif scenario == "process_noise_switch":
        primary_candidate_indices = process_indices.copy()
    else:
        primary_candidate_indices = joint_candidate_indices.copy()
    origin_joint_candidate_indices = np.asarray(
        [lookup[pair] for pair in origin_pairs], dtype=np.int64
    )

    return ThreeStageTruthSchedule(
        scenario=scenario,
        primary_method_name=primary_method_name,
        joint_candidate_indices=joint_candidate_indices,
        parameter_indices=parameter_indices,
        process_indices=process_indices,
        primary_candidate_indices=primary_candidate_indices,
        origin_joint_candidate_indices=origin_joint_candidate_indices,
        stage_start_days=stage_start_days,
        stage_end_days=stage_end_days,
    )


def _integer_seeds(values: Sequence[int], count: int, label: str) -> np.ndarray:
    raw = tuple(values)
    if len(raw) != count or any(isinstance(value, bool) for value in raw):
        raise ValueError(f"{label} must contain one integer per block")
    converted = np.asarray(raw, dtype=np.int64)
    if any(int(converted[index]) != raw[index] for index in range(count)):
        raise ValueError(f"{label} must contain integers")
    return converted


def _validated_leads(values: Sequence[int]) -> np.ndarray:
    raw = tuple(values)
    if not raw or any(
        isinstance(value, bool) or not isinstance(value, (int, np.integer))
        for value in raw
    ):
        raise ValueError("lead_days must contain positive increasing integers")
    leads = np.asarray(raw, dtype=np.int64)
    if np.any(leads <= 0) or np.any(np.diff(leads) <= 0):
        raise ValueError("lead_days must contain positive increasing integers")
    return leads


def _initial_covariance(center_state: np.ndarray, covariance_fraction: float) -> np.ndarray:
    scales = np.maximum(np.abs(center_state), 1.0)
    return np.diag(np.square(covariance_fraction * scales))


def _method_candidate_contracts(
    definitions: Mapping[str, Sequence[MethodCandidate]],
) -> tuple[tuple[str, ...], ...]:
    return (
        ("trained_center_open_loop",),
        tuple(candidate.candidate_id for candidate in definitions["fixed_filter"]),
        tuple(candidate.candidate_id for candidate in definitions["parameter_only"]),
        tuple(candidate.candidate_id for candidate in definitions["noise_only"]),
        tuple(candidate.candidate_id for candidate in definitions["joint"]),
    )


def _assimilate_record_then_forecast(
    candidates: Sequence[MethodCandidate],
    initial_states: Mapping[str, np.ndarray],
    covariance: np.ndarray,
    active_forcing: np.ndarray,
    observations: np.ndarray,
    assimilation_days: int,
    leads: np.ndarray,
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
):
    bank = build_method_bank(
        candidates=candidates,
        initial_states=initial_states,
        initial_covariance=covariance,
        observation_standard_deviation=observation_standard_deviation,
        factor_transition_stay_probability=factor_transition_stay_probability,
        interaction_mode="full",
    )
    probabilities = np.empty((assimilation_days, len(candidates)), dtype=np.float64)
    states = np.empty((assimilation_days, 15), dtype=np.float64)
    for day in range(assimilation_days):
        rain, potential_evaporation, temperature = active_forcing[day]
        for transition in bank.transitions:
            transition.set_forcing(rain, potential_evaporation, temperature)
        bank.estimator.step(observations[day])
        probabilities[day] = bank.estimator.probabilities
        states[day] = bank.estimator.state
    future = active_forcing[assimilation_days : assimilation_days + int(leads[-1])]
    forecast = forecast_from_posterior(
        bank,
        future,
        lead_days=tuple(int(value) for value in leads),
        interaction_mode="full",
    )
    return probabilities, states, bank.estimator.state.copy(), forecast


def run_three_stage_switching_validation(
    forcing_blocks,
    block_ids: Sequence[str],
    parameter_vectors: Mapping[str, Mapping[str, float]],
    process_scales: Mapping[str, float],
    process_covariances: Mapping[str, np.ndarray],
    selected_process_id: str,
    scenario: str,
    process_noise_seeds: Sequence[int],
    observation_noise_seeds: Sequence[int],
    warmup_days: int,
    stage_lengths: Sequence[int],
    lead_days: Sequence[int],
    initial_covariance_fraction: float,
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
    future_observation_replacement: float | None = None,
) -> ThreeStageSwitchingValidationResult:
    """Run one exact-candidate three-stage switching truth through matched methods.

    Forecast probabilities stay at the final assimilation posterior; the
    model-switching transition matrix is used only during assimilation.
    """

    forcing_values = np.asarray(forcing_blocks, dtype=np.float64)
    if forcing_values.ndim != 3 or forcing_values.shape[2] != 3:
        raise ValueError("forcing_blocks must have shape (blocks, days, 3)")
    block_count, forcing_days, _ = forcing_values.shape
    if block_count == 0 or not np.all(np.isfinite(forcing_values)):
        raise ValueError("forcing_blocks must contain finite values")
    blocks = tuple(str(value) for value in block_ids)
    if (
        len(blocks) != block_count
        or len(set(blocks)) != block_count
        or any(not value for value in blocks)
    ):
        raise ValueError("block_ids must contain one unique nonempty identifier per block")
    process_seeds = _integer_seeds(
        process_noise_seeds, block_count, "process_noise_seeds"
    )
    observation_seeds = _integer_seeds(
        observation_noise_seeds, block_count, "observation_noise_seeds"
    )
    if (
        isinstance(warmup_days, bool)
        or int(warmup_days) != warmup_days
        or int(warmup_days) <= 0
    ):
        raise ValueError("warmup_days must be a positive integer")
    warmup = int(warmup_days)
    leads = _validated_leads(lead_days)
    definitions = build_method_definitions(
        parameter_vectors=parameter_vectors,
        process_scales=process_scales,
        process_covariances=process_covariances,
        selected_process_id=selected_process_id,
    )
    schedule = build_three_stage_truth_schedule(
        definitions=definitions,
        scenario=scenario,
        selected_process_id=selected_process_id,
        stage_lengths=stage_lengths,
        forecast_days=int(leads[-1]),
    )
    assimilation_days = int(schedule.stage_end_days[-1])
    active_days = assimilation_days + int(leads[-1])
    if forcing_days != warmup + active_days:
        raise ValueError(
            "forcing blocks must exactly cover warmup, three stages and maximum lead"
        )
    covariance_fraction = float(initial_covariance_fraction)
    observation_std = float(observation_standard_deviation)
    stay_probability = float(factor_transition_stay_probability)
    if not np.isfinite(covariance_fraction) or covariance_fraction <= 0.0:
        raise ValueError("initial_covariance_fraction must be finite and positive")
    if not np.isfinite(observation_std) or observation_std <= 0.0:
        raise ValueError("observation_standard_deviation must be finite and positive")
    if not np.isfinite(stay_probability) or not 0.0 <= stay_probability <= 1.0:
        raise ValueError(
            "factor_transition_stay_probability must be between zero and one"
        )
    if future_observation_replacement is not None and not np.isfinite(
        float(future_observation_replacement)
    ):
        raise ValueError("future_observation_replacement must be finite")

    joint_candidates = tuple(definitions["joint"])
    parameter_ids = tuple(
        dict.fromkeys(candidate.parameter_id for candidate in joint_candidates)
    )
    process_ids = tuple(
        dict.fromkeys(candidate.process_id for candidate in joint_candidates)
    )
    candidate_contracts = _method_candidate_contracts(definitions)
    candidate_counts = np.asarray(
        [len(values) for values in candidate_contracts], dtype=np.int64
    )
    truth_count = schedule.joint_candidate_indices.shape[0]
    method_count = len(METHOD_NAMES)
    lead_count = len(leads)
    parameter_count = len(parameter_ids)

    initial_parameter_states = np.empty(
        (block_count, parameter_count, 15), dtype=np.float64
    )
    initial_covariances = np.empty((block_count, 15, 15), dtype=np.float64)
    process_normals = np.empty((block_count, active_days, 15), dtype=np.float64)
    observation_normals = np.empty((block_count, active_days), dtype=np.float64)
    truth_shape = (block_count, truth_count, active_days, 15)
    truth_deterministic_states = np.empty(truth_shape, dtype=np.float64)
    truth_process_perturbations = np.empty(truth_shape, dtype=np.float64)
    truth_projection_adjustments = np.empty(truth_shape, dtype=np.float64)
    truth_states = np.empty(truth_shape, dtype=np.float64)
    truth_discharge = np.empty((block_count, truth_count, active_days), dtype=np.float64)
    observed_discharge = np.empty_like(truth_discharge)
    truth_forecasts = np.empty((block_count, truth_count, lead_count), dtype=np.float64)
    assimilation_probabilities = np.zeros(
        (block_count, truth_count, method_count, assimilation_days, 9),
        dtype=np.float64,
    )
    assimilation_states = np.empty(
        (block_count, truth_count, method_count, assimilation_days, 15),
        dtype=np.float64,
    )
    method_origin_states = np.empty(
        (block_count, truth_count, method_count, 15), dtype=np.float64
    )
    method_predictions = np.empty(
        (block_count, truth_count, method_count, lead_count), dtype=np.float64
    )
    method_candidate_predictions = np.zeros(
        (block_count, truth_count, method_count, lead_count, 9), dtype=np.float64
    )
    method_forecast_probabilities = np.zeros_like(method_candidate_predictions)
    forecast_indices = assimilation_days + leads - 1

    parameter_index = {value: index for index, value in enumerate(parameter_ids)}
    parameter_values = {
        str(key): {name: float(value) for name, value in values.items()}
        for key, values in parameter_vectors.items()
    }
    process_covariance_values = {
        str(key): np.asarray(value, dtype=np.float64)
        for key, value in process_covariances.items()
    }

    for block in range(block_count):
        forcing = forcing_values[block]
        warm_forcing = forcing[:warmup]
        active_forcing = forcing[warmup:]
        initial_states: dict[str, np.ndarray] = {}
        for parameter_id in parameter_ids:
            state = generate_reference_truth(
                warm_forcing, parameter_values[parameter_id]
            ).states[-1]
            initial_states[parameter_id] = state
            initial_parameter_states[block, parameter_index[parameter_id]] = state
        covariance = _initial_covariance(
            initial_states["trained_center"], covariance_fraction
        )
        initial_covariances[block] = covariance
        process_normals[block] = np.random.default_rng(
            int(process_seeds[block])
        ).standard_normal((active_days, 15))
        observation_normals[block] = np.random.default_rng(
            int(observation_seeds[block])
        ).standard_normal(active_days)

        open_discharge, open_states = simulate_adapter(
            active_forcing[:, 0],
            active_forcing[:, 1],
            active_forcing[:, 2],
            parameter_values["trained_center"],
            initial_state=initial_states["trained_center"],
        )
        for truth_index in range(truth_count):
            initial_candidate = joint_candidates[
                int(schedule.joint_candidate_indices[truth_index, 0])
            ]
            truth_state = initial_states[initial_candidate.parameter_id].copy()
            for day in range(active_days):
                candidate = joint_candidates[
                    int(schedule.joint_candidate_indices[truth_index, day])
                ]
                parameters = parameter_values[candidate.parameter_id]
                process_covariance = process_covariance_values[candidate.process_id]
                rain, potential_evaporation, temperature = active_forcing[day]
                deterministic_state = advance_reference_state(
                    truth_state,
                    rain,
                    potential_evaporation,
                    temperature,
                    parameters,
                )
                perturbation = process_normals[block, day] * np.sqrt(
                    np.diag(process_covariance)
                )
                unprojected_state = deterministic_state + perturbation
                projected_state = project_reference_state(unprojected_state, parameters)
                discharge = reference_routed_discharge(
                    projected_state, parameters["lag_time"]
                )
                truth_deterministic_states[block, truth_index, day] = deterministic_state
                truth_process_perturbations[block, truth_index, day] = perturbation
                truth_projection_adjustments[block, truth_index, day] = (
                    projected_state - unprojected_state
                )
                truth_states[block, truth_index, day] = projected_state
                truth_discharge[block, truth_index, day] = discharge
                observed_discharge[block, truth_index, day] = (
                    discharge + observation_std * observation_normals[block, day]
                )
                truth_state = projected_state
            if future_observation_replacement is not None:
                observed_discharge[
                    block, truth_index, assimilation_days:
                ] = float(future_observation_replacement)

            truth_forecasts[block, truth_index] = truth_discharge[
                block, truth_index, forecast_indices
            ]
            assimilation_probabilities[block, truth_index, 0, :, 0] = 1.0
            assimilation_states[block, truth_index, 0] = open_states[:assimilation_days]
            method_origin_states[block, truth_index, 0] = open_states[
                assimilation_days - 1
            ]
            method_predictions[block, truth_index, 0] = open_discharge[forecast_indices]
            method_candidate_predictions[block, truth_index, 0, :, 0] = (
                open_discharge[forecast_indices]
            )
            method_forecast_probabilities[block, truth_index, 0, :, 0] = 1.0

            for method_index, method_name in enumerate(METHOD_NAMES[1:], start=1):
                daily_probabilities, daily_states, origin_state, forecast = (
                    _assimilate_record_then_forecast(
                        candidates=definitions[method_name],
                        initial_states=initial_states,
                        covariance=covariance,
                        active_forcing=active_forcing,
                        observations=observed_discharge[block, truth_index],
                        assimilation_days=assimilation_days,
                        leads=leads,
                        observation_standard_deviation=observation_std,
                        factor_transition_stay_probability=stay_probability,
                    )
                )
                count = len(definitions[method_name])
                assimilation_probabilities[
                    block, truth_index, method_index, :, :count
                ] = daily_probabilities
                assimilation_states[block, truth_index, method_index] = daily_states
                method_origin_states[block, truth_index, method_index] = origin_state
                method_predictions[block, truth_index, method_index] = (
                    forecast.combined_predictions
                )
                method_candidate_predictions[
                    block, truth_index, method_index, :, :count
                ] = forecast.candidate_predictions
                method_forecast_probabilities[
                    block, truth_index, method_index, :, :count
                ] = forecast.probabilities

    method_absolute_errors = np.abs(
        method_predictions - truth_forecasts[:, :, None, :]
    )
    return ThreeStageSwitchingValidationResult(
        scenario=scenario,
        schedule=schedule,
        block_ids=blocks,
        process_noise_seeds=process_seeds.copy(),
        observation_noise_seeds=observation_seeds.copy(),
        forcing_blocks=forcing_values.copy(),
        warmup_days=warmup,
        stage_lengths=np.asarray(tuple(stage_lengths), dtype=np.int64),
        assimilation_days=assimilation_days,
        forecast_lead_days=leads.copy(),
        method_names=METHOD_NAMES,
        method_candidate_ids=candidate_contracts,
        method_candidate_counts=candidate_counts,
        parameter_ids=parameter_ids,
        process_ids=process_ids,
        initial_parameter_states=initial_parameter_states,
        initial_covariances=initial_covariances,
        process_standard_normals=process_normals,
        observation_standard_normals=observation_normals,
        truth_deterministic_states=truth_deterministic_states,
        truth_process_perturbations=truth_process_perturbations,
        truth_projection_adjustments=truth_projection_adjustments,
        truth_states=truth_states,
        truth_discharge=truth_discharge,
        observed_discharge=observed_discharge,
        truth_forecast_discharge=truth_forecasts,
        method_assimilation_probabilities=assimilation_probabilities,
        method_assimilation_states=assimilation_states,
        method_origin_states=method_origin_states,
        method_predictions=method_predictions,
        method_candidate_predictions=method_candidate_predictions,
        method_forecast_probabilities=method_forecast_probabilities,
        method_absolute_errors=method_absolute_errors,
    )


def _bootstrap_mean_interval(
    values: np.ndarray, replicates: int, seed: int
) -> tuple[float, float]:
    if values.ndim != 1 or len(values) == 0 or int(replicates) <= 0:
        raise ValueError("bootstrap values and replicates must be nonempty")
    rng = np.random.default_rng(int(seed))
    indices = rng.integers(0, len(values), size=(int(replicates), len(values)))
    statistics = np.mean(values[indices], axis=1)
    lower, upper = np.quantile(statistics, [0.025, 0.975])
    return float(lower), float(upper)


def evaluate_three_stage_switching_result(
    result: ThreeStageSwitchingValidationResult,
    adaptation_days: int,
    bootstrap_replicates: int,
    bootstrap_seed: int,
    candidate_accuracy_minimum: float,
    factor_accuracy_minimum: float,
    median_true_probability_minimum: float,
    relative_root_mean_square_error_improvement_percent_minimum: float,
    paired_block_difference_upper_maximum: float,
) -> dict:
    """Recompute stage identification and forecast decisions from raw arrays."""

    adaptation = int(adaptation_days)
    if (
        isinstance(adaptation_days, bool)
        or adaptation != adaptation_days
        or adaptation < 0
        or np.any(result.stage_lengths <= adaptation)
    ):
        raise ValueError("adaptation_days must leave at least one evaluated day per stage")
    method_index = {name: index for index, name in enumerate(result.method_names)}
    primary_index = method_index[result.schedule.primary_method_name]
    primary_count = int(result.method_candidate_counts[primary_index])
    primary_probabilities = result.method_assimilation_probabilities[
        :, :, primary_index, :, :primary_count
    ]
    truth_labels = result.schedule.primary_candidate_indices[
        :, : result.assimilation_days
    ]
    joint_probabilities = result.method_assimilation_probabilities[
        :, :, method_index["joint"], :, :9
    ]
    joint_grid = joint_probabilities.reshape(
        *joint_probabilities.shape[:-1], 3, 3
    )
    parameter_marginals = joint_grid.sum(axis=-1)
    process_marginals = joint_grid.sum(axis=-2)
    parameter_truth = result.schedule.parameter_indices[:, : result.assimilation_days]
    process_truth = result.schedule.process_indices[:, : result.assimilation_days]

    stage_rows = []
    for stage_index, (start, end) in enumerate(
        zip(result.schedule.stage_start_days, result.schedule.stage_end_days)
    ):
        evaluated_start = int(start) + adaptation
        evaluated_end = int(end)
        selected = primary_probabilities[:, :, evaluated_start:evaluated_end]
        selected_truth = truth_labels[:, evaluated_start:evaluated_end]
        expanded_truth = np.broadcast_to(selected_truth[None, ...], selected.shape[:-1])
        true_probabilities = np.take_along_axis(
            selected, expanded_truth[..., None], axis=-1
        )[..., 0]
        candidate_accuracy = float(
            np.mean(np.argmax(selected, axis=-1) == expanded_truth)
        )

        selected_parameter = parameter_marginals[
            :, :, evaluated_start:evaluated_end
        ]
        selected_process = process_marginals[:, :, evaluated_start:evaluated_end]
        expanded_parameter_truth = np.broadcast_to(
            parameter_truth[None, :, evaluated_start:evaluated_end],
            selected_parameter.shape[:-1],
        )
        expanded_process_truth = np.broadcast_to(
            process_truth[None, :, evaluated_start:evaluated_end],
            selected_process.shape[:-1],
        )
        parameter_accuracy = float(
            np.mean(
                np.argmax(selected_parameter, axis=-1) == expanded_parameter_truth
            )
        )
        process_accuracy = float(
            np.mean(np.argmax(selected_process, axis=-1) == expanded_process_truth)
        )
        median_true_probability = float(np.median(true_probabilities))
        if result.scenario == "parameter_switch":
            passed = bool(
                candidate_accuracy >= factor_accuracy_minimum
                and median_true_probability >= median_true_probability_minimum
            )
        elif result.scenario == "process_noise_switch":
            passed = bool(
                candidate_accuracy >= factor_accuracy_minimum
                and median_true_probability >= median_true_probability_minimum
            )
        else:
            passed = bool(
                candidate_accuracy >= candidate_accuracy_minimum
                and parameter_accuracy >= factor_accuracy_minimum
                and process_accuracy >= factor_accuracy_minimum
                and median_true_probability >= median_true_probability_minimum
            )
        stage_rows.append(
            {
                "stage_number": stage_index + 1,
                "stage_start_day_one_based": int(start) + 1,
                "stage_end_day_one_based": int(end),
                "adaptation_days_excluded": adaptation,
                "evaluated_day_count_per_truth": evaluated_end - evaluated_start,
                "evaluated_value_count": int(true_probabilities.size),
                "primary_candidate_argmax_accuracy": candidate_accuracy,
                "joint_parameter_marginal_argmax_accuracy": parameter_accuracy,
                "joint_process_marginal_argmax_accuracy": process_accuracy,
                "median_primary_true_candidate_probability": median_true_probability,
                "identification_passed": passed,
            }
        )

    method_metrics = []
    paired_rows = []
    forecast_rows = []
    block_root_mean_square_errors = np.sqrt(
        np.mean(np.square(result.method_absolute_errors), axis=1)
    )
    fixed_index = method_index["fixed_filter"]
    for lead_index, lead in enumerate(result.forecast_lead_days):
        for name, index in method_index.items():
            errors = result.method_absolute_errors[:, :, index, lead_index]
            method_metrics.append(
                {
                    "scenario": result.scenario,
                    "method": name,
                    "lead_days": int(lead),
                    "root_mean_square_error": float(
                        np.sqrt(np.mean(np.square(errors)))
                    ),
                    "median_absolute_error": float(np.median(errors)),
                    "matched_block_count": len(result.block_ids),
                    "truth_trial_count_per_block": truth_labels.shape[0],
                }
            )
        comparisons = ["fixed_filter"]
        if result.scenario == "parameter_process_noise_switch":
            comparisons.extend(("parameter_only", "noise_only"))
        comparison_decisions = {}
        for comparison_offset, control_name in enumerate(comparisons):
            control_index = method_index[control_name]
            primary_global = float(
                np.sqrt(
                    np.mean(
                        np.square(
                            result.method_absolute_errors[
                                :, :, primary_index, lead_index
                            ]
                        )
                    )
                )
            )
            control_global = float(
                np.sqrt(
                    np.mean(
                        np.square(
                            result.method_absolute_errors[
                                :, :, control_index, lead_index
                            ]
                        )
                    )
                )
            )
            differences = (
                block_root_mean_square_errors[:, primary_index, lead_index]
                - block_root_mean_square_errors[:, control_index, lead_index]
            )
            lower, upper = _bootstrap_mean_interval(
                differences,
                bootstrap_replicates,
                int(bootstrap_seed) + 100 * lead_index + comparison_offset,
            )
            improvement = float(
                100.0 * (control_global - primary_global) / control_global
            )
            paired_rows.append(
                {
                    "scenario": result.scenario,
                    "lead_days": int(lead),
                    "primary_method": result.schedule.primary_method_name,
                    "control_method": control_name,
                    "primary_root_mean_square_error": primary_global,
                    "control_root_mean_square_error": control_global,
                    "relative_improvement_percent": improvement,
                    "mean_paired_block_root_mean_square_error_difference": float(
                        np.mean(differences)
                    ),
                    "paired_block_difference_bootstrap_lower": lower,
                    "paired_block_difference_bootstrap_upper": upper,
                    "primary_better_block_count": int(
                        np.count_nonzero(differences < 0.0)
                    ),
                    "matched_block_count": len(result.block_ids),
                }
            )
            comparison_decisions[control_name] = {
                "relative_improvement_percent": improvement,
                "paired_block_difference_bootstrap_upper": upper,
            }
        fixed = comparison_decisions["fixed_filter"]
        effective_against_fixed = bool(
            fixed["relative_improvement_percent"]
            >= relative_root_mean_square_error_improvement_percent_minimum
            and fixed["paired_block_difference_bootstrap_upper"]
            < paired_block_difference_upper_maximum
        )
        if result.scenario == "parameter_process_noise_switch":
            added_value = bool(
                effective_against_fixed
                and comparison_decisions["parameter_only"][
                    "paired_block_difference_bootstrap_upper"
                ]
                < paired_block_difference_upper_maximum
                and comparison_decisions["noise_only"][
                    "paired_block_difference_bootstrap_upper"
                ]
                < paired_block_difference_upper_maximum
            )
        else:
            added_value = None
        forecast_rows.append(
            {
                "lead_days": int(lead),
                "primary_method": result.schedule.primary_method_name,
                "effective_against_fixed_filter": effective_against_fixed,
                "added_value_beyond_both_single_factor_methods": added_value,
            }
        )

    projection_events = np.any(
        result.truth_projection_adjustments != 0.0, axis=-1
    )
    identification_passed = bool(
        all(row["identification_passed"] for row in stage_rows)
    )
    forecast_passed = bool(
        all(
            row["added_value_beyond_both_single_factor_methods"]
            if result.scenario == "parameter_process_noise_switch"
            else row["effective_against_fixed_filter"]
            for row in forecast_rows
        )
    )
    return {
        "scenario": result.scenario,
        "stage_identification": stage_rows,
        "identification_passed_all_three_stages": identification_passed,
        "forecast_decisions": forecast_rows,
        "forecast_passed_all_leads": forecast_passed,
        "scientific_success": bool(identification_passed and forecast_passed),
        "method_metrics": method_metrics,
        "paired_comparisons": paired_rows,
        "truth_process_interpretation": {
            "pre_projection_covariance_uses_current_frozen_candidate": True,
            "post_projection_distribution_matches_additive_gaussian_candidate": False,
            "projection_event_count": int(np.count_nonzero(projection_events)),
            "projection_event_total": int(projection_events.size),
            "projection_event_fraction": float(np.mean(projection_events)),
        },
        "decision_rules": {
            "candidate_accuracy_minimum": float(candidate_accuracy_minimum),
            "factor_accuracy_minimum": float(factor_accuracy_minimum),
            "median_true_probability_minimum": float(
                median_true_probability_minimum
            ),
            "relative_root_mean_square_error_improvement_percent_minimum": float(
                relative_root_mean_square_error_improvement_percent_minimum
            ),
            "paired_block_difference_upper_maximum": float(
                paired_block_difference_upper_maximum
            ),
        },
    }
