"""Closed-truth identification of three fixed process-noise covariances."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np

from hbv_joint_uncertainty.imm import normalize_log_weights
from hbv_joint_uncertainty.preflight import (
    ForcingTransition,
    RoutedDischargeObservation,
    project_hbv_state,
)
from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter

from .synthetic_truth import (
    advance_reference_state,
    generate_reference_truth,
    project_reference_state,
    reference_routed_discharge,
)


@dataclass(frozen=True)
class ProcessNoiseIdentificationValidationResult:
    trial_ids: tuple[str, ...]
    forcing_block_ids: tuple[str, ...]
    process_noise_ids: tuple[str, str, str]
    true_process_noise_ids: tuple[str, ...]
    process_noise_seeds: np.ndarray
    observation_noise_seeds: np.ndarray
    process_covariances: np.ndarray
    initial_truth_states: np.ndarray
    truth_deterministic_states: np.ndarray
    process_standard_normals: np.ndarray
    truth_process_perturbations: np.ndarray
    truth_projection_adjustments: np.ndarray
    truth_states: np.ndarray
    truth_discharge: np.ndarray
    observation_standard_normals: np.ndarray
    observed_discharge: np.ndarray
    candidate_prior_discharge: np.ndarray
    candidate_innovation_variances: np.ndarray
    candidate_log_likelihoods: np.ndarray
    posterior_probabilities: np.ndarray
    candidate_posterior_states: np.ndarray


def _integer_array(values: Sequence[int], size: int, label: str) -> np.ndarray:
    raw = tuple(values)
    if len(raw) != size or any(isinstance(value, bool) for value in raw):
        raise ValueError(f"{label} must contain one integer per trial")
    converted = np.asarray(raw, dtype=np.int64)
    if any(int(converted[index]) != raw[index] for index in range(size)):
        raise ValueError(f"{label} must contain one integer per trial")
    return converted


def _validated_covariances(
    process_covariances: Mapping[str, np.ndarray],
) -> tuple[tuple[str, str, str], np.ndarray]:
    process_ids = tuple(str(value) for value in process_covariances)
    if len(process_ids) != 3 or len(set(process_ids)) != 3:
        raise ValueError("process_covariances must contain exactly three uniquely named candidates")
    matrices = []
    for process_id in process_ids:
        covariance = np.asarray(process_covariances[process_id], dtype=np.float64)
        if covariance.shape != (15, 15) or not np.all(np.isfinite(covariance)):
            raise ValueError(f"process covariance {process_id!r} must be a finite 15 by 15 matrix")
        if not np.array_equal(covariance, np.diag(np.diag(covariance))):
            raise ValueError(f"process covariance {process_id!r} must be diagonal")
        diagonal = np.diag(covariance)
        if np.any(diagonal[:5] <= 0.0):
            raise ValueError(f"process covariance {process_id!r} hydrologic variances must be positive")
        if np.any(diagonal[5:] != 0.0):
            raise ValueError(f"process covariance {process_id!r} routing-memory variances must be zero")
        matrices.append(covariance.copy())
    stacked = np.stack(matrices)
    for left in range(3):
        for right in range(left + 1, 3):
            if np.array_equal(stacked[left], stacked[right]):
                raise ValueError("the three process covariance candidates must be distinct")
    return process_ids, stacked


def run_process_noise_identification_validation(
    forcing_realizations,
    trial_ids: Sequence[str],
    forcing_block_ids: Sequence[str],
    parameter_vector: Mapping[str, float],
    process_covariances: Mapping[str, np.ndarray],
    true_process_noise_ids: Sequence[str],
    process_noise_seeds: Sequence[int],
    observation_noise_seeds: Sequence[int],
    start_day: int,
    duration_days: int,
    initial_covariance_fraction: float,
    observation_standard_deviation: float,
) -> ProcessNoiseIdentificationValidationResult:
    """Score three fixed process covariances without switching or state interaction."""
    forcing_values = np.asarray(forcing_realizations, dtype=np.float64)
    if forcing_values.ndim != 3 or forcing_values.shape[2] != 3:
        raise ValueError("forcing_realizations must have shape (trials, days, 3)")
    trial_count, day_count, _ = forcing_values.shape
    if not np.all(np.isfinite(forcing_values)):
        raise ValueError("forcing_realizations must be finite")
    trials = tuple(str(value) for value in trial_ids)
    blocks = tuple(str(value) for value in forcing_block_ids)
    if len(trials) != trial_count or len(set(trials)) != trial_count:
        raise ValueError("trial_ids must contain one unique value per trial")
    if len(blocks) != trial_count or any(not value for value in blocks):
        raise ValueError("forcing_block_ids must contain one nonempty value per trial")
    process_ids, covariance_values = _validated_covariances(process_covariances)
    truth_ids = tuple(str(value) for value in true_process_noise_ids)
    if len(truth_ids) != trial_count:
        raise ValueError("true_process_noise_ids must contain one label per trial")
    unknown_truth = set(truth_ids) - set(process_ids)
    if unknown_truth:
        raise ValueError(f"unknown true process-noise labels: {sorted(unknown_truth)}")
    process_seeds = _integer_array(process_noise_seeds, trial_count, "process_noise_seeds")
    observation_seeds = _integer_array(
        observation_noise_seeds, trial_count, "observation_noise_seeds"
    )

    start = int(start_day)
    duration = int(duration_days)
    if isinstance(start_day, bool) or start != start_day or start <= 0:
        raise ValueError("start_day must be a positive integer")
    if isinstance(duration_days, bool) or duration != duration_days or duration <= 0:
        raise ValueError("duration_days must be a positive integer")
    if start + duration > day_count:
        raise ValueError("assimilation period exceeds the forcing realization length")
    covariance_fraction = float(initial_covariance_fraction)
    observation_std = float(observation_standard_deviation)
    if not np.isfinite(covariance_fraction) or covariance_fraction <= 0.0:
        raise ValueError("initial_covariance_fraction must be finite and positive")
    if not np.isfinite(observation_std) or observation_std <= 0.0:
        raise ValueError("observation_standard_deviation must be finite and positive")
    parameters = {name: float(value) for name, value in parameter_vector.items()}

    candidate_count = 3
    initial_truth_states = np.empty((trial_count, 15), dtype=np.float64)
    truth_deterministic_states = np.empty((trial_count, duration, 15), dtype=np.float64)
    process_standard_normals = np.empty_like(truth_deterministic_states)
    truth_process_perturbations = np.empty_like(truth_deterministic_states)
    truth_projection_adjustments = np.empty_like(truth_deterministic_states)
    truth_states = np.empty_like(truth_deterministic_states)
    truth_discharge = np.empty((trial_count, duration), dtype=np.float64)
    observation_standard_normals = np.empty((trial_count, duration), dtype=np.float64)
    observed_discharge = np.empty_like(observation_standard_normals)
    candidate_prior_discharge = np.empty(
        (trial_count, duration, candidate_count), dtype=np.float64
    )
    candidate_innovation_variances = np.empty_like(candidate_prior_discharge)
    candidate_log_likelihoods = np.empty_like(candidate_prior_discharge)
    posterior_probabilities = np.empty_like(candidate_prior_discharge)
    candidate_posterior_states = np.empty(
        (trial_count, duration, candidate_count, 15), dtype=np.float64
    )
    observation_covariance = np.asarray([[observation_std**2]], dtype=np.float64)
    process_index = {process_id: index for index, process_id in enumerate(process_ids)}

    for trial in range(trial_count):
        forcing = forcing_values[trial]
        reference = generate_reference_truth(forcing, parameters)
        initial_state = project_hbv_state(reference.states[start - 1], parameters)
        initial_truth_states[trial] = initial_state
        scales = np.maximum(np.abs(initial_state), 1.0)
        initial_covariance = np.diag(np.square(covariance_fraction * scales))
        filters = []
        candidate_transitions = []
        for covariance in covariance_values:
            transition = ForcingTransition(parameters)
            observation = RoutedDischargeObservation(parameters)
            projector = lambda values, p=parameters: project_hbv_state(values, p)
            filters.append(
                ModifiedUnscentedFilter(
                    state=initial_state.copy(),
                    covariance=initial_covariance.copy(),
                    transition=transition,
                    observation=observation,
                    process_covariance=covariance.copy(),
                    observation_covariance=observation_covariance.copy(),
                    state_projector=projector,
                    alpha=0.6874,
                    beta=2.0,
                    kappa=-2.0,
                )
            )
            candidate_transitions.append(transition)

        truth_state = initial_state.copy()
        process_rng = np.random.default_rng(int(process_seeds[trial]))
        observation_rng = np.random.default_rng(int(observation_seeds[trial]))
        standard_process = process_rng.standard_normal((duration, 15))
        standard_observation = observation_rng.standard_normal(duration)
        process_standard_normals[trial] = standard_process
        observation_standard_normals[trial] = standard_observation
        true_covariance = covariance_values[process_index[truth_ids[trial]]]
        process_scale = np.sqrt(np.diag(true_covariance))
        cumulative_log_likelihood = np.zeros(candidate_count, dtype=np.float64)

        for offset, day in enumerate(range(start, start + duration)):
            rain, potential_evaporation, temperature = forcing[day]
            deterministic_state = advance_reference_state(
                truth_state,
                rain,
                potential_evaporation,
                temperature,
                parameters,
            )
            perturbation = standard_process[offset] * process_scale
            unprojected_state = deterministic_state + perturbation
            projected_state = project_reference_state(unprojected_state, parameters)
            discharge = reference_routed_discharge(
                projected_state, parameters["lag_time"]
            )
            observation_value = discharge + observation_std * standard_observation[offset]
            truth_deterministic_states[trial, offset] = deterministic_state
            truth_process_perturbations[trial, offset] = perturbation
            truth_projection_adjustments[trial, offset] = projected_state - unprojected_state
            truth_states[trial, offset] = projected_state
            truth_discharge[trial, offset] = discharge
            observed_discharge[trial, offset] = observation_value
            truth_state = projected_state

            for candidate, (estimator, transition) in enumerate(
                zip(filters, candidate_transitions)
            ):
                transition.set_forcing(rain, potential_evaporation, temperature)
                step = estimator.step(observation_value)
                candidate_prior_discharge[trial, offset, candidate] = step.prior_observation[0]
                candidate_innovation_variances[trial, offset, candidate] = (
                    step.innovation_covariance[0, 0]
                )
                candidate_log_likelihoods[trial, offset, candidate] = step.log_likelihood
                candidate_posterior_states[trial, offset, candidate] = step.posterior_state
                cumulative_log_likelihood[candidate] += step.log_likelihood
            posterior_probabilities[trial, offset] = normalize_log_weights(
                cumulative_log_likelihood
            )

    return ProcessNoiseIdentificationValidationResult(
        trial_ids=trials,
        forcing_block_ids=blocks,
        process_noise_ids=process_ids,
        true_process_noise_ids=truth_ids,
        process_noise_seeds=process_seeds.copy(),
        observation_noise_seeds=observation_seeds.copy(),
        process_covariances=covariance_values,
        initial_truth_states=initial_truth_states,
        truth_deterministic_states=truth_deterministic_states,
        process_standard_normals=process_standard_normals,
        truth_process_perturbations=truth_process_perturbations,
        truth_projection_adjustments=truth_projection_adjustments,
        truth_states=truth_states,
        truth_discharge=truth_discharge,
        observation_standard_normals=observation_standard_normals,
        observed_discharge=observed_discharge,
        candidate_prior_discharge=candidate_prior_discharge,
        candidate_innovation_variances=candidate_innovation_variances,
        candidate_log_likelihoods=candidate_log_likelihoods,
        posterior_probabilities=posterior_probabilities,
        candidate_posterior_states=candidate_posterior_states,
    )
