"""Closed-truth identification of three fixed complete parameter vectors."""

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

from .synthetic_truth import generate_reference_truth


@dataclass(frozen=True)
class ParameterIdentificationValidationResult:
    forcing_realization_ids: np.ndarray
    parameter_ids: tuple[str, str, str]
    true_parameter_ids: tuple[str, ...]
    truth_discharge: np.ndarray
    candidate_prior_discharge: np.ndarray
    candidate_log_likelihoods: np.ndarray
    posterior_probabilities: np.ndarray
    candidate_posterior_states: np.ndarray
    process_covariance: np.ndarray


def run_parameter_identification_validation(
    forcing_realizations,
    forcing_realization_ids: Sequence[int],
    parameter_vectors: Mapping[str, Mapping[str, float]],
    true_parameter_ids: Sequence[str],
    start_day: int,
    duration_days: int,
    initial_covariance_fraction: float,
    observation_standard_deviation: float,
) -> ParameterIdentificationValidationResult:
    """Update fixed-model probabilities without switching or state interaction."""
    forcing_values = np.asarray(forcing_realizations, dtype=np.float64)
    realization_ids = np.asarray(tuple(forcing_realization_ids), dtype=np.int64)
    parameter_ids = tuple(parameter_vectors)
    truth_ids = tuple(str(value) for value in true_parameter_ids)
    if forcing_values.ndim != 3 or forcing_values.shape[2] != 3:
        raise ValueError("forcing_realizations must have shape (trials, days, 3)")
    trial_count, day_count, _ = forcing_values.shape
    if realization_ids.shape != (trial_count,) or len(set(realization_ids.tolist())) != trial_count:
        raise ValueError("forcing_realization_ids must contain one unique value per trial")
    if len(parameter_ids) != 3 or len(set(parameter_ids)) != 3:
        raise ValueError("parameter_vectors must contain exactly three uniquely named vectors")
    if len(truth_ids) != trial_count:
        raise ValueError("true_parameter_ids must contain one label per trial")
    unknown_truth = set(truth_ids) - set(parameter_ids)
    if unknown_truth:
        raise ValueError(f"unknown true parameter labels: {sorted(unknown_truth)}")
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
    if not np.all(np.isfinite(forcing_values)):
        raise ValueError("forcing_realizations must be finite")

    vectors = {
        parameter_id: {name: float(value) for name, value in parameters.items()}
        for parameter_id, parameters in parameter_vectors.items()
    }
    candidate_count = len(parameter_ids)
    truth_discharge = np.empty((trial_count, duration), dtype=np.float64)
    candidate_prior_discharge = np.empty(
        (trial_count, duration, candidate_count), dtype=np.float64
    )
    candidate_log_likelihoods = np.empty_like(candidate_prior_discharge)
    posterior_probabilities = np.empty_like(candidate_prior_discharge)
    candidate_posterior_states = np.empty(
        (trial_count, duration, candidate_count, 15), dtype=np.float64
    )
    process_covariance = np.zeros((15, 15), dtype=np.float64)
    observation_covariance = np.asarray([[observation_std**2]], dtype=np.float64)

    for trial in range(trial_count):
        forcing = forcing_values[trial]
        references = {
            parameter_id: generate_reference_truth(forcing, vectors[parameter_id])
            for parameter_id in parameter_ids
        }
        filters = []
        transitions = []
        for parameter_id in parameter_ids:
            parameters = vectors[parameter_id]
            initial_state = references[parameter_id].states[start - 1].copy()
            initial_state = project_hbv_state(initial_state, parameters)
            scales = np.maximum(np.abs(initial_state), 1.0)
            transition = ForcingTransition(parameters)
            observation = RoutedDischargeObservation(parameters)
            projector = lambda values, p=parameters: project_hbv_state(values, p)
            filters.append(
                ModifiedUnscentedFilter(
                    state=initial_state,
                    covariance=np.diag(np.square(covariance_fraction * scales)),
                    transition=transition,
                    observation=observation,
                    process_covariance=process_covariance.copy(),
                    observation_covariance=observation_covariance.copy(),
                    state_projector=projector,
                    alpha=0.6874,
                    beta=2.0,
                    kappa=-2.0,
                )
            )
            transitions.append(transition)

        cumulative_log_likelihood = np.zeros(candidate_count, dtype=np.float64)
        truth = references[truth_ids[trial]]
        for offset, day in enumerate(range(start, start + duration)):
            rain, potential_evaporation, temperature = forcing[day]
            observation_value = truth.discharge[day]
            truth_discharge[trial, offset] = observation_value
            for candidate, (estimator, transition) in enumerate(zip(filters, transitions)):
                transition.set_forcing(rain, potential_evaporation, temperature)
                step = estimator.step(observation_value)
                candidate_prior_discharge[trial, offset, candidate] = step.prior_observation[0]
                candidate_log_likelihoods[trial, offset, candidate] = step.log_likelihood
                candidate_posterior_states[trial, offset, candidate] = step.posterior_state
                cumulative_log_likelihood[candidate] += step.log_likelihood
            posterior_probabilities[trial, offset] = normalize_log_weights(
                cumulative_log_likelihood
            )

    return ParameterIdentificationValidationResult(
        forcing_realization_ids=realization_ids.copy(),
        parameter_ids=parameter_ids,
        true_parameter_ids=truth_ids,
        truth_discharge=truth_discharge,
        candidate_prior_discharge=candidate_prior_discharge,
        candidate_log_likelihoods=candidate_log_likelihoods,
        posterior_probabilities=posterior_probabilities,
        candidate_posterior_states=candidate_posterior_states,
        process_covariance=process_covariance,
    )
