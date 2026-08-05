"""Closed stable-truth validation of the complete nine-filter joint method."""

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


METHOD_NAMES = (
    "open_loop",
    "fixed_filter",
    "parameter_only",
    "noise_only",
    "joint",
    "oracle_filter",
)
DEFAULT_STATE_NORMALIZATION_SCALES = np.asarray(
    [100.0, 5.0, 200.0, 20.0, 100.0], dtype=np.float64
)


@dataclass(frozen=True)
class StableJointMethodValidationResult:
    block_ids: tuple[str, ...]
    process_noise_seeds: np.ndarray
    observation_noise_seeds: np.ndarray
    forcing_blocks: np.ndarray
    warmup_days: int
    assimilation_days: int
    forecast_lead_days: np.ndarray
    method_names: tuple[str, ...]
    method_candidate_ids: tuple[tuple[str, ...], ...]
    method_candidate_counts: np.ndarray
    parameter_ids: tuple[str, str, str]
    process_ids: tuple[str, str, str]
    truth_candidate_ids: tuple[str, ...]
    truth_candidate_factors: tuple[tuple[str, str], ...]
    truth_candidate_schedules: np.ndarray
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
    method_predictions: np.ndarray
    method_candidate_predictions: np.ndarray
    method_probabilities: np.ndarray
    method_origin_states: np.ndarray
    method_origin_state_normalized_root_mean_square_errors: np.ndarray
    method_absolute_errors: np.ndarray
    joint_origin_probabilities: np.ndarray
    joint_origin_true_probabilities: np.ndarray
    joint_origin_true_parameter_probabilities: np.ndarray
    joint_origin_true_process_probabilities: np.ndarray
    state_normalization_scales: np.ndarray


def _integer_seeds(values: Sequence[int], count: int, label: str) -> np.ndarray:
    raw = tuple(values)
    if len(raw) != count or any(isinstance(value, bool) for value in raw):
        raise ValueError(f"{label} must contain one integer per block")
    converted = np.asarray(raw, dtype=np.int64)
    if any(int(converted[index]) != raw[index] for index in range(count)):
        raise ValueError(f"{label} must contain integers")
    return converted


def _validate_leads(values: Sequence[int]) -> np.ndarray:
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


def _method_candidate_contracts(
    definitions: dict[str, tuple[MethodCandidate, ...]],
) -> tuple[tuple[str, ...], ...]:
    return (
        ("trained_center_open_loop",),
        tuple(candidate.candidate_id for candidate in definitions["fixed_filter"]),
        tuple(candidate.candidate_id for candidate in definitions["parameter_only"]),
        tuple(candidate.candidate_id for candidate in definitions["noise_only"]),
        tuple(candidate.candidate_id for candidate in definitions["joint"]),
        ("truth_specific_oracle",),
    )


def _initial_covariance(
    center_state: np.ndarray, covariance_fraction: float
) -> np.ndarray:
    scales = np.maximum(np.abs(center_state), 1.0)
    return np.diag(np.square(covariance_fraction * scales))


def _assimilate_then_forecast(
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
    for day in range(assimilation_days):
        rain, potential_evaporation, temperature = active_forcing[day]
        for transition in bank.transitions:
            transition.set_forcing(rain, potential_evaporation, temperature)
        bank.estimator.step(observations[day])
    origin_state = bank.estimator.global_posterior_state
    origin_probabilities = bank.estimator.probabilities.copy()
    future = active_forcing[
        assimilation_days : assimilation_days + int(leads[-1])
    ]
    forecast = forecast_from_posterior(
        bank,
        future,
        lead_days=tuple(int(value) for value in leads),
        interaction_mode="full",
    )
    return origin_state, origin_probabilities, forecast


def run_stable_joint_method_validation(
    forcing_blocks,
    block_ids: Sequence[str],
    parameter_vectors: Mapping[str, Mapping[str, float]],
    process_scales: Mapping[str, float],
    process_covariances: Mapping[str, np.ndarray],
    selected_process_id: str,
    process_noise_seeds: Sequence[int],
    observation_noise_seeds: Sequence[int],
    warmup_days: int,
    assimilation_days: int,
    lead_days: Sequence[int],
    initial_covariance_fraction: float,
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
    truth_switch_period_days: int | None = None,
    truth_switch_candidate_step: int = 4,
    state_normalization_scales=DEFAULT_STATE_NORMALIZATION_SCALES,
) -> StableJointMethodValidationResult:
    """Run matched fixed or periodically switching truths through fair controls."""
    forcing_values = np.asarray(forcing_blocks, dtype=np.float64)
    if forcing_values.ndim != 3 or forcing_values.shape[2] != 3:
        raise ValueError("forcing_blocks must have shape (blocks, days, 3)")
    block_count, forcing_days, _ = forcing_values.shape
    if block_count == 0 or not np.all(np.isfinite(forcing_values)):
        raise ValueError("forcing_blocks must contain finite values")
    blocks = tuple(str(value) for value in block_ids)
    if len(blocks) != block_count or len(set(blocks)) != block_count or any(not value for value in blocks):
        raise ValueError("block_ids must contain one unique nonempty identifier per block")
    process_seeds = _integer_seeds(
        process_noise_seeds, block_count, "process_noise_seeds"
    )
    observation_seeds = _integer_seeds(
        observation_noise_seeds, block_count, "observation_noise_seeds"
    )
    warmup = int(warmup_days)
    assimilation = int(assimilation_days)
    leads = _validate_leads(lead_days)
    if (
        isinstance(warmup_days, bool)
        or warmup != warmup_days
        or warmup <= 0
        or isinstance(assimilation_days, bool)
        or assimilation != assimilation_days
        or assimilation <= 0
    ):
        raise ValueError("warmup_days and assimilation_days must be positive integers")
    active_days = assimilation + int(leads[-1])
    if forcing_days != warmup + active_days:
        raise ValueError("forcing blocks must exactly cover warmup, assimilation and maximum lead")
    covariance_fraction = float(initial_covariance_fraction)
    observation_std = float(observation_standard_deviation)
    stay_probability = float(factor_transition_stay_probability)
    if not np.isfinite(covariance_fraction) or covariance_fraction <= 0.0:
        raise ValueError("initial_covariance_fraction must be finite and positive")
    if not np.isfinite(observation_std) or observation_std <= 0.0:
        raise ValueError("observation_standard_deviation must be finite and positive")
    if not np.isfinite(stay_probability) or stay_probability < 0.0 or stay_probability > 1.0:
        raise ValueError("factor_transition_stay_probability must be between zero and one")
    state_scales = np.asarray(state_normalization_scales, dtype=np.float64)
    if state_scales.shape != (5,) or not np.all(np.isfinite(state_scales)) or np.any(state_scales <= 0.0):
        raise ValueError("state_normalization_scales must contain five finite positive values")

    definitions = build_method_definitions(
        parameter_vectors=parameter_vectors,
        process_scales=process_scales,
        process_covariances=process_covariances,
        selected_process_id=selected_process_id,
    )
    joint_candidates = definitions["joint"]
    parameter_ids = tuple(dict.fromkeys(candidate.parameter_id for candidate in joint_candidates))
    process_ids = tuple(dict.fromkeys(candidate.process_id for candidate in joint_candidates))
    if len(parameter_ids) != 3 or len(process_ids) != 3 or len(joint_candidates) != 9:
        raise ValueError("the joint method must contain three parameter by three process candidates")
    truth_factors = tuple(
        (candidate.parameter_id, candidate.process_id) for candidate in joint_candidates
    )
    truth_ids = tuple(candidate.candidate_id for candidate in joint_candidates)
    if truth_switch_period_days is None:
        truth_schedules = np.repeat(
            np.arange(9, dtype=np.int64)[:, None], active_days, axis=1
        )
    else:
        switch_period = int(truth_switch_period_days)
        switch_step = int(truth_switch_candidate_step)
        if (
            isinstance(truth_switch_period_days, bool)
            or switch_period != truth_switch_period_days
            or switch_period <= 0
        ):
            raise ValueError("truth_switch_period_days must be a positive integer")
        if (
            isinstance(truth_switch_candidate_step, bool)
            or switch_step != truth_switch_candidate_step
            or switch_step <= 0
            or switch_step >= 9
            or np.gcd(switch_step, 9) != 1
        ):
            raise ValueError(
                "truth_switch_candidate_step must be an integer from one through eight coprime with nine"
            )
        segments = np.arange(active_days, dtype=np.int64) // switch_period
        origin_segment = (assimilation - 1) // switch_period
        truth_schedules = np.empty((9, active_days), dtype=np.int64)
        for origin_candidate in range(9):
            start_candidate = (
                origin_candidate - switch_step * origin_segment
            ) % 9
            truth_schedules[origin_candidate] = (
                start_candidate + switch_step * segments
            ) % 9
        if not np.array_equal(
            truth_schedules[:, assimilation - 1], np.arange(9, dtype=np.int64)
        ):
            raise RuntimeError("switch schedule does not align origin truth labels")
    candidate_contracts = _method_candidate_contracts(definitions)
    candidate_counts = np.asarray(
        [len(values) for values in candidate_contracts], dtype=np.int64
    )

    parameter_count = 3
    truth_count = 9
    method_count = len(METHOD_NAMES)
    lead_count = len(leads)
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
    method_predictions = np.empty(
        (block_count, truth_count, method_count, lead_count), dtype=np.float64
    )
    method_candidate_predictions = np.zeros(
        (block_count, truth_count, method_count, lead_count, 9), dtype=np.float64
    )
    method_probabilities = np.zeros_like(method_candidate_predictions)
    method_origin_states = np.empty(
        (block_count, truth_count, method_count, 15), dtype=np.float64
    )
    joint_origin_probabilities = np.empty(
        (block_count, truth_count, truth_count), dtype=np.float64
    )
    forecast_indices = assimilation + leads - 1

    parameter_index = {value: index for index, value in enumerate(parameter_ids)}
    process_index = {value: index for index, value in enumerate(process_ids)}
    process_covariance_values = {
        str(key): np.asarray(value, dtype=np.float64)
        for key, value in process_covariances.items()
    }
    parameter_values = {
        str(key): {name: float(value) for name, value in values.items()}
        for key, values in parameter_vectors.items()
    }

    for block in range(block_count):
        forcing = forcing_values[block]
        warm_forcing = forcing[:warmup]
        active_forcing = forcing[warmup:]
        initial_states = {}
        for parameter_id in parameter_ids:
            initial_state = generate_reference_truth(
                warm_forcing, parameter_values[parameter_id]
            ).states[-1]
            initial_states[parameter_id] = initial_state
            initial_parameter_states[
                block, parameter_index[parameter_id]
            ] = initial_state
        covariance = _initial_covariance(
            initial_states["trained_center"], covariance_fraction
        )
        initial_covariances[block] = covariance
        process_rng = np.random.default_rng(int(process_seeds[block]))
        observation_rng = np.random.default_rng(int(observation_seeds[block]))
        process_normals[block] = process_rng.standard_normal((active_days, 15))
        observation_normals[block] = observation_rng.standard_normal(active_days)

        open_discharge, open_states = simulate_adapter(
            active_forcing[:, 0],
            active_forcing[:, 1],
            active_forcing[:, 2],
            parameter_values["trained_center"],
            initial_state=initial_states["trained_center"],
        )
        for truth_index in range(truth_count):
            initial_truth_candidate = joint_candidates[
                int(truth_schedules[truth_index, 0])
            ]
            truth_state = initial_states[initial_truth_candidate.parameter_id].copy()
            for day in range(active_days):
                truth_candidate = joint_candidates[
                    int(truth_schedules[truth_index, day])
                ]
                parameters = parameter_values[truth_candidate.parameter_id]
                process_covariance = process_covariance_values[
                    truth_candidate.process_id
                ]
                process_scale = np.sqrt(np.diag(process_covariance))
                rain, potential_evaporation, temperature = active_forcing[day]
                deterministic_state = advance_reference_state(
                    truth_state,
                    rain,
                    potential_evaporation,
                    temperature,
                    parameters,
                )
                perturbation = process_normals[block, day] * process_scale
                unprojected_state = deterministic_state + perturbation
                projected_state = project_reference_state(
                    unprojected_state, parameters
                )
                discharge = reference_routed_discharge(
                    projected_state, parameters["lag_time"]
                )
                truth_deterministic_states[
                    block, truth_index, day
                ] = deterministic_state
                truth_process_perturbations[
                    block, truth_index, day
                ] = perturbation
                truth_projection_adjustments[
                    block, truth_index, day
                ] = projected_state - unprojected_state
                truth_states[block, truth_index, day] = projected_state
                truth_discharge[block, truth_index, day] = discharge
                observed_discharge[block, truth_index, day] = (
                    discharge + observation_std * observation_normals[block, day]
                )
                truth_state = projected_state

            truth_forecasts[block, truth_index] = truth_discharge[
                block, truth_index, forecast_indices
            ]
            method_predictions[block, truth_index, 0] = open_discharge[
                forecast_indices
            ]
            method_candidate_predictions[block, truth_index, 0, :, 0] = (
                open_discharge[forecast_indices]
            )
            method_probabilities[block, truth_index, 0, :, 0] = 1.0
            method_origin_states[block, truth_index, 0] = open_states[
                assimilation - 1
            ]

            for method_index, method_name in enumerate(METHOD_NAMES[1:5], start=1):
                origin_state, origin_probabilities, forecast = _assimilate_then_forecast(
                    candidates=definitions[method_name],
                    initial_states=initial_states,
                    covariance=covariance,
                    active_forcing=active_forcing,
                    observations=observed_discharge[block, truth_index],
                    assimilation_days=assimilation,
                    leads=leads,
                    observation_standard_deviation=observation_std,
                    factor_transition_stay_probability=stay_probability,
                )
                count = len(definitions[method_name])
                method_predictions[
                    block, truth_index, method_index
                ] = forecast.combined_predictions
                method_candidate_predictions[
                    block, truth_index, method_index, :, :count
                ] = forecast.candidate_predictions
                method_probabilities[
                    block, truth_index, method_index, :, :count
                ] = forecast.probabilities
                method_origin_states[
                    block, truth_index, method_index
                ] = origin_state
                if method_name == "joint":
                    joint_origin_probabilities[
                        block, truth_index
                    ] = origin_probabilities

            oracle_candidate = (joint_candidates[truth_index],)
            oracle_state, _, oracle_forecast = _assimilate_then_forecast(
                candidates=oracle_candidate,
                initial_states=initial_states,
                covariance=covariance,
                active_forcing=active_forcing,
                observations=observed_discharge[block, truth_index],
                assimilation_days=assimilation,
                leads=leads,
                observation_standard_deviation=observation_std,
                factor_transition_stay_probability=stay_probability,
            )
            method_predictions[block, truth_index, 5] = (
                oracle_forecast.combined_predictions
            )
            method_candidate_predictions[block, truth_index, 5, :, 0] = (
                oracle_forecast.candidate_predictions[:, 0]
            )
            method_probabilities[block, truth_index, 5, :, 0] = 1.0
            method_origin_states[block, truth_index, 5] = oracle_state

    truth_origin_states = truth_states[:, :, assimilation - 1]
    normalized_differences = (
        method_origin_states[:, :, :, :5] - truth_origin_states[:, :, None, :5]
    ) / state_scales[None, None, None, :]
    method_origin_state_errors = np.sqrt(
        np.mean(np.square(normalized_differences), axis=-1)
    )
    method_absolute_errors = np.abs(
        method_predictions - truth_forecasts[:, :, None, :]
    )
    trial_indices = np.arange(truth_count)
    true_probabilities = joint_origin_probabilities[:, trial_indices, trial_indices]
    probability_grid = joint_origin_probabilities.reshape(
        block_count, truth_count, 3, 3
    )
    true_parameter_indices = np.asarray(
        [parameter_index[parameter_id] for parameter_id, _ in truth_factors]
    )
    true_process_indices = np.asarray(
        [process_index[process_id] for _, process_id in truth_factors]
    )
    parameter_marginals = probability_grid.sum(axis=3)
    process_marginals = probability_grid.sum(axis=2)
    true_parameter_probabilities = np.empty((block_count, truth_count), dtype=np.float64)
    true_process_probabilities = np.empty_like(true_parameter_probabilities)
    for truth_index in range(truth_count):
        true_parameter_probabilities[:, truth_index] = parameter_marginals[
            :, truth_index, true_parameter_indices[truth_index]
        ]
        true_process_probabilities[:, truth_index] = process_marginals[
            :, truth_index, true_process_indices[truth_index]
        ]

    return StableJointMethodValidationResult(
        block_ids=blocks,
        process_noise_seeds=process_seeds.copy(),
        observation_noise_seeds=observation_seeds.copy(),
        forcing_blocks=forcing_values.copy(),
        warmup_days=warmup,
        assimilation_days=assimilation,
        forecast_lead_days=leads.copy(),
        method_names=METHOD_NAMES,
        method_candidate_ids=candidate_contracts,
        method_candidate_counts=candidate_counts,
        parameter_ids=parameter_ids,
        process_ids=process_ids,
        truth_candidate_ids=truth_ids,
        truth_candidate_factors=truth_factors,
        truth_candidate_schedules=truth_schedules.copy(),
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
        method_predictions=method_predictions,
        method_candidate_predictions=method_candidate_predictions,
        method_probabilities=method_probabilities,
        method_origin_states=method_origin_states,
        method_origin_state_normalized_root_mean_square_errors=(
            method_origin_state_errors
        ),
        method_absolute_errors=method_absolute_errors,
        joint_origin_probabilities=joint_origin_probabilities,
        joint_origin_true_probabilities=true_probabilities,
        joint_origin_true_parameter_probabilities=true_parameter_probabilities,
        joint_origin_true_process_probabilities=true_process_probabilities,
        state_normalization_scales=state_scales.copy(),
    )
