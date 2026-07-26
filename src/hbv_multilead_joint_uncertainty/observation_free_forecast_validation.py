"""Independent numerical validation of causal observation-free forecasts."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

import numpy as np

from hbv_multilead_joint_uncertainty.forecast import forecast_from_posterior
from hbv_multilead_joint_uncertainty.methods import MethodCandidate, build_method_bank
from hbv_multilead_joint_uncertainty.synthetic_truth import (
    advance_reference_state,
    generate_reference_truth,
    project_reference_state,
    reference_routed_discharge,
)


@dataclass(frozen=True)
class ObservationFreeForecastValidationResult:
    trial_seeds: np.ndarray
    forcing_realizations: np.ndarray
    warmup_days: int
    forecast_days: int
    candidate_ids: tuple[str, ...]
    parameter_ids: tuple[str, ...]
    process_ids: tuple[str, ...]
    initial_probabilities: np.ndarray
    initial_candidate_states: np.ndarray
    initial_candidate_covariances: np.ndarray
    source_candidate_states_after_forecasts: np.ndarray
    source_candidate_covariances_after_forecasts: np.ndarray
    source_probabilities_after_forecasts: np.ndarray
    production_combined_predictions: np.ndarray
    production_candidate_predictions: np.ndarray
    production_probabilities: np.ndarray
    production_candidate_states: np.ndarray
    production_candidate_covariance_diagonals: np.ndarray
    production_combined_states: np.ndarray
    production_combined_covariance_diagonals: np.ndarray
    reference_combined_predictions: np.ndarray
    reference_candidate_predictions: np.ndarray
    reference_probabilities: np.ndarray
    reference_candidate_states: np.ndarray
    reference_candidate_covariances: np.ndarray
    reference_combined_states: np.ndarray
    reference_combined_covariances: np.ndarray
    production_selected_combined_predictions: np.ndarray
    production_selected_candidate_predictions: np.ndarray
    production_selected_probabilities: np.ndarray
    production_selected_candidate_states: np.ndarray
    production_selected_candidate_covariance_diagonals: np.ndarray
    production_selected_combined_states: np.ndarray
    production_selected_combined_covariance_diagonals: np.ndarray
    production_three_day_combined_predictions: np.ndarray
    production_three_day_candidate_predictions: np.ndarray
    production_three_day_probabilities: np.ndarray
    production_three_day_candidate_states: np.ndarray
    production_three_day_candidate_covariance_diagonals: np.ndarray
    production_three_day_combined_states: np.ndarray
    production_three_day_combined_covariance_diagonals: np.ndarray
    maximum_source_state_mutation: float
    maximum_source_covariance_mutation: float
    maximum_source_probability_mutation: float




def _reference_sigma_points(
    mean: np.ndarray,
    covariance: np.ndarray,
    alpha: float = 0.6874,
    beta: float = 2.0,
    kappa: float = -2.0,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    values = np.asarray(mean, dtype=np.float64)
    matrix = np.asarray(covariance, dtype=np.float64)
    if values.shape != (15,) or matrix.shape != (15, 15):
        raise ValueError("reference moments must have fifteen state dimensions")
    matrix = 0.5 * (matrix + matrix.T)
    if not np.all(np.isfinite(values)) or not np.all(np.isfinite(matrix)):
        raise ValueError("reference moments must be finite")
    state_count = len(values)
    lambda_value = alpha**2 * (state_count + kappa) - state_count
    scale = state_count + lambda_value
    mean_weights = np.full(2 * state_count + 1, 1.0 / (2.0 * scale), dtype=np.float64)
    covariance_weights = mean_weights.copy()
    mean_weights[0] = lambda_value / scale
    covariance_weights[0] = mean_weights[0] + 1.0 - alpha**2 + beta
    eigenvalues = np.linalg.eigvalsh(matrix)
    minimum = float(np.min(eigenvalues))
    spectral_scale = max(float(np.max(np.abs(eigenvalues))), 1.0)
    tolerance = max(
        1e-12,
        np.finfo(np.float64).eps * state_count * spectral_scale * 100.0,
    )
    if minimum < -tolerance:
        raise ValueError(
            "reference covariance is not positive semidefinite; "
            f"minimum eigenvalue is {minimum}"
        )
    try:
        root = np.linalg.cholesky(scale * matrix)
    except np.linalg.LinAlgError:
        jitter = max(tolerance, -minimum + tolerance)
        root = np.linalg.cholesky(scale * (matrix + jitter * np.eye(state_count)))
    sigmas = np.empty((2 * state_count + 1, state_count), dtype=np.float64)
    sigmas[0] = values
    for index in range(state_count):
        offset = root[:, index]
        sigmas[index + 1] = values + offset
        sigmas[state_count + index + 1] = values - offset
    return sigmas, mean_weights, covariance_weights


def _reference_moments(
    points: np.ndarray,
    mean_weights: np.ndarray,
    covariance_weights: np.ndarray,
    additive_covariance: np.ndarray | None = None,
) -> tuple[np.ndarray, np.ndarray]:
    mean = mean_weights @ points
    deviations = points - mean
    covariance = np.zeros((points.shape[1], points.shape[1]), dtype=np.float64)
    for weight, deviation in zip(covariance_weights, deviations):
        covariance += weight * np.outer(deviation, deviation)
    if additive_covariance is not None:
        covariance += additive_covariance
    return mean, 0.5 * (covariance + covariance.T)




def _reference_predict_candidate(
    state: np.ndarray,
    covariance: np.ndarray,
    forcing: np.ndarray,
    candidate: MethodCandidate,
) -> tuple[np.ndarray, np.ndarray, float]:
    sigmas, mean_weights, covariance_weights = _reference_sigma_points(state, covariance)
    rain, potential_evaporation, temperature = forcing
    transformed = np.asarray(
        [
            advance_reference_state(
                project_reference_state(point, candidate.parameters),
                rain,
                potential_evaporation,
                temperature,
                candidate.parameters,
            )
            for point in sigmas
        ],
        dtype=np.float64,
    )
    predicted_state, predicted_covariance = _reference_moments(
        transformed,
        mean_weights,
        covariance_weights,
        candidate.process_covariance,
    )
    observation_sigmas, observation_mean_weights, _ = _reference_sigma_points(
        predicted_state, predicted_covariance
    )
    observations = np.asarray(
        [
            reference_routed_discharge(
                project_reference_state(point, candidate.parameters),
                candidate.parameters["lag_time"],
            )
            for point in observation_sigmas
        ],
        dtype=np.float64,
    )
    prediction = float(observation_mean_weights @ observations)
    return predicted_state, predicted_covariance, prediction


def _reference_forecast(
    candidates: tuple[MethodCandidate, ...],
    initial_states: np.ndarray,
    initial_covariances: np.ndarray,
    initial_probabilities: np.ndarray,
    forcing: np.ndarray,
):
    day_count = len(forcing)
    candidate_count, state_count = initial_states.shape
    probabilities = initial_probabilities.copy()
    states = initial_states.copy()
    covariances = initial_covariances.copy()
    saved_probabilities = np.empty((day_count, candidate_count), dtype=np.float64)
    saved_states = np.empty((day_count, candidate_count, state_count), dtype=np.float64)
    saved_covariances = np.empty(
        (day_count, candidate_count, state_count, state_count), dtype=np.float64
    )
    candidate_predictions = np.empty((day_count, candidate_count), dtype=np.float64)
    combined_predictions = np.empty(day_count, dtype=np.float64)
    combined_states = np.empty((day_count, state_count), dtype=np.float64)
    combined_covariances = np.empty((day_count, state_count, state_count), dtype=np.float64)
    for day in range(day_count):
        for candidate_index, candidate in enumerate(candidates):
            states[candidate_index], covariances[candidate_index], candidate_predictions[
                day, candidate_index
            ] = _reference_predict_candidate(
                states[candidate_index],
                covariances[candidate_index],
                forcing[day],
                candidate,
            )
        combined_state = probabilities @ states
        combined_covariance = np.zeros((state_count, state_count), dtype=np.float64)
        for probability, state, covariance in zip(probabilities, states, covariances):
            difference = state - combined_state
            combined_covariance += probability * (
                covariance + np.outer(difference, difference)
            )
        saved_probabilities[day] = probabilities
        saved_states[day] = states
        saved_covariances[day] = covariances
        combined_predictions[day] = probabilities @ candidate_predictions[day]
        combined_states[day] = combined_state
        combined_covariances[day] = 0.5 * (
            combined_covariance + combined_covariance.T
        )
    return (
        combined_predictions,
        candidate_predictions,
        saved_probabilities,
        saved_states,
        saved_covariances,
        combined_states,
        combined_covariances,
    )


def _maximum_difference(left: np.ndarray, right: np.ndarray) -> float:
    return float(np.max(np.abs(np.asarray(left) - np.asarray(right)), initial=0.0))


def run_observation_free_forecast_validation(
    trial_seeds: Sequence[int],
    forcing_realizations,
    warmup_days: int,
    forecast_days: int,
    candidates: Sequence[MethodCandidate],
    initial_covariance,
    initial_probabilities,
    observation_standard_deviation: float,
) -> ObservationFreeForecastValidationResult:
    """Compare production forecasts with a separate simulator and moment recursion."""
    definitions = tuple(candidates)
    seeds = np.asarray(tuple(trial_seeds), dtype=np.int64)
    forcing_values = np.asarray(forcing_realizations, dtype=np.float64)
    if seeds.ndim != 1 or len(seeds) == 0 or len(set(seeds.tolist())) != len(seeds):
        raise ValueError("trial_seeds must contain unique integers")
    if forcing_values.ndim != 3 or forcing_values.shape[0] != len(seeds) or forcing_values.shape[2] != 3:
        raise ValueError("forcing_realizations must have shape (trials, days, 3)")
    warmup = int(warmup_days)
    forecast_count = int(forecast_days)
    if (
        isinstance(warmup_days, bool)
        or warmup != warmup_days
        or warmup <= 0
        or isinstance(forecast_days, bool)
        or forecast_count != forecast_days
        or forecast_count < 7
        or forcing_values.shape[1] != warmup + forecast_count
    ):
        raise ValueError("forcing must contain positive warmup days and at least seven forecast days")
    if len(definitions) != 9:
        raise ValueError("candidates must contain nine definitions")
    covariance = np.asarray(initial_covariance, dtype=np.float64)
    if covariance.shape != (15, 15) or not np.all(np.isfinite(covariance)):
        raise ValueError("initial_covariance must be one finite fifteen by fifteen matrix")
    probabilities = np.asarray(initial_probabilities, dtype=np.float64)
    if probabilities.shape != (9,) or np.any(probabilities <= 0.0) or not np.all(np.isfinite(probabilities)):
        raise ValueError("initial_probabilities must contain nine finite positive values")
    if not np.isclose(probabilities.sum(), 1.0, rtol=0.0, atol=1e-12):
        raise ValueError("initial_probabilities must sum to one")
    probabilities = probabilities / probabilities.sum()

    trial_count = len(seeds)
    production_combined = np.empty((trial_count, forecast_count), dtype=np.float64)
    production_candidates = np.empty((trial_count, forecast_count, 9), dtype=np.float64)
    production_probabilities = np.empty_like(production_candidates)
    production_states = np.empty((trial_count, forecast_count, 9, 15), dtype=np.float64)
    production_covariance_diagonals = np.empty_like(production_states)
    production_combined_states = np.empty((trial_count, forecast_count, 15), dtype=np.float64)
    production_combined_covariance_diagonals = np.empty_like(production_combined_states)
    reference_combined = np.empty_like(production_combined)
    reference_candidates = np.empty_like(production_candidates)
    reference_probabilities = np.empty_like(production_probabilities)
    reference_states = np.empty_like(production_states)
    reference_covariances = np.empty(
        (trial_count, forecast_count, 9, 15, 15), dtype=np.float64
    )
    reference_combined_states = np.empty_like(production_combined_states)
    reference_combined_covariances = np.empty(
        (trial_count, forecast_count, 15, 15), dtype=np.float64
    )
    initial_states = np.empty((trial_count, 9, 15), dtype=np.float64)
    initial_covariances = np.empty((trial_count, 9, 15, 15), dtype=np.float64)
    source_states_after = np.empty_like(initial_states)
    source_covariances_after = np.empty_like(initial_covariances)
    source_probabilities_after = np.empty((trial_count, 9), dtype=np.float64)

    selected_combined = np.empty((trial_count, 3), dtype=np.float64)
    selected_candidates = np.empty((trial_count, 3, 9), dtype=np.float64)
    selected_probabilities = np.empty_like(selected_candidates)
    selected_states = np.empty((trial_count, 3, 9, 15), dtype=np.float64)
    selected_covariance_diagonals = np.empty_like(selected_states)
    selected_combined_states = np.empty((trial_count, 3, 15), dtype=np.float64)
    selected_combined_covariance_diagonals = np.empty_like(selected_combined_states)
    short_combined = np.empty((trial_count, 3), dtype=np.float64)
    short_candidates = np.empty((trial_count, 3, 9), dtype=np.float64)
    short_probabilities = np.empty_like(short_candidates)
    short_states = np.empty((trial_count, 3, 9, 15), dtype=np.float64)
    short_covariance_diagonals = np.empty_like(short_states)
    short_combined_states = np.empty((trial_count, 3, 15), dtype=np.float64)
    short_combined_covariance_diagonals = np.empty_like(short_combined_states)
    state_mutation = 0.0
    covariance_mutation = 0.0
    probability_mutation = 0.0

    parameter_ids = tuple(dict.fromkeys(candidate.parameter_id for candidate in definitions))
    for trial in range(trial_count):
        warm_forcing = forcing_values[trial, :warmup]
        state_by_parameter = {
            parameter_id: generate_reference_truth(
                warm_forcing,
                next(
                    candidate.parameters
                    for candidate in definitions
                    if candidate.parameter_id == parameter_id
                ),
            ).states[-1]
            for parameter_id in parameter_ids
        }
        bank = build_method_bank(
            candidates=definitions,
            initial_states=state_by_parameter,
            initial_covariance=covariance,
            observation_standard_deviation=observation_standard_deviation,
            # A non-identity assimilation matrix must still be ignored by the forecast.
            factor_transition_stay_probability=0.98,
            interaction_mode="full",
        )
        bank.estimator.probabilities = probabilities.copy()
        before_states = np.asarray([candidate.state.copy() for candidate in bank.estimator.filters])
        before_covariances = np.asarray(
            [candidate.covariance.copy() for candidate in bank.estimator.filters]
        )
        before_probabilities = bank.estimator.probabilities.copy()
        initial_states[trial] = before_states
        initial_covariances[trial] = before_covariances
        future = forcing_values[trial, warmup:]
        full = forecast_from_posterior(
            bank,
            future,
            lead_days=tuple(range(1, forecast_count + 1)),
            interaction_mode="full",
        )
        selected = forecast_from_posterior(
            bank, future, lead_days=(1, 3, 7), interaction_mode="full"
        )
        short = forecast_from_posterior(
            bank,
            future[:3],
            lead_days=(1, 2, 3),
            interaction_mode="full",
        )
        production_combined[trial] = full.combined_predictions
        production_candidates[trial] = full.candidate_predictions
        production_probabilities[trial] = full.probabilities
        production_states[trial] = full.candidate_states
        production_covariance_diagonals[trial] = full.candidate_covariance_diagonals
        production_combined_states[trial] = full.combined_states
        production_combined_covariance_diagonals[trial] = full.combined_covariance_diagonals
        selected_combined[trial] = selected.combined_predictions
        selected_candidates[trial] = selected.candidate_predictions
        selected_probabilities[trial] = selected.probabilities
        selected_states[trial] = selected.candidate_states
        selected_covariance_diagonals[trial] = selected.candidate_covariance_diagonals
        selected_combined_states[trial] = selected.combined_states
        selected_combined_covariance_diagonals[trial] = selected.combined_covariance_diagonals
        short_combined[trial] = short.combined_predictions
        short_candidates[trial] = short.candidate_predictions
        short_probabilities[trial] = short.probabilities
        short_states[trial] = short.candidate_states
        short_covariance_diagonals[trial] = short.candidate_covariance_diagonals
        short_combined_states[trial] = short.combined_states
        short_combined_covariance_diagonals[trial] = short.combined_covariance_diagonals
        (
            reference_combined[trial],
            reference_candidates[trial],
            reference_probabilities[trial],
            reference_states[trial],
            reference_covariances[trial],
            reference_combined_states[trial],
            reference_combined_covariances[trial],
        ) = _reference_forecast(
            definitions,
            before_states,
            before_covariances,
            probabilities,
            future,
        )
        state_mutation = max(
            state_mutation,
            _maximum_difference(
                before_states,
                np.asarray([candidate.state for candidate in bank.estimator.filters]),
            ),
        )
        covariance_mutation = max(
            covariance_mutation,
            _maximum_difference(
                before_covariances,
                np.asarray([candidate.covariance for candidate in bank.estimator.filters]),
            ),
        )
        probability_mutation = max(
            probability_mutation,
            _maximum_difference(before_probabilities, bank.estimator.probabilities),
        )
        source_states_after[trial] = np.asarray(
            [candidate.state for candidate in bank.estimator.filters]
        )
        source_covariances_after[trial] = np.asarray(
            [candidate.covariance for candidate in bank.estimator.filters]
        )
        source_probabilities_after[trial] = bank.estimator.probabilities

    return ObservationFreeForecastValidationResult(
        trial_seeds=seeds.copy(),
        forcing_realizations=forcing_values.copy(),
        warmup_days=warmup,
        forecast_days=forecast_count,
        candidate_ids=tuple(candidate.candidate_id for candidate in definitions),
        parameter_ids=tuple(candidate.parameter_id for candidate in definitions),
        process_ids=tuple(candidate.process_id for candidate in definitions),
        initial_probabilities=probabilities.copy(),
        initial_candidate_states=initial_states,
        initial_candidate_covariances=initial_covariances,
        source_candidate_states_after_forecasts=source_states_after,
        source_candidate_covariances_after_forecasts=source_covariances_after,
        source_probabilities_after_forecasts=source_probabilities_after,
        production_combined_predictions=production_combined,
        production_candidate_predictions=production_candidates,
        production_probabilities=production_probabilities,
        production_candidate_states=production_states,
        production_candidate_covariance_diagonals=production_covariance_diagonals,
        production_combined_states=production_combined_states,
        production_combined_covariance_diagonals=production_combined_covariance_diagonals,
        reference_combined_predictions=reference_combined,
        reference_candidate_predictions=reference_candidates,
        reference_probabilities=reference_probabilities,
        reference_candidate_states=reference_states,
        reference_candidate_covariances=reference_covariances,
        reference_combined_states=reference_combined_states,
        reference_combined_covariances=reference_combined_covariances,
        production_selected_combined_predictions=selected_combined,
        production_selected_candidate_predictions=selected_candidates,
        production_selected_probabilities=selected_probabilities,
        production_selected_candidate_states=selected_states,
        production_selected_candidate_covariance_diagonals=selected_covariance_diagonals,
        production_selected_combined_states=selected_combined_states,
        production_selected_combined_covariance_diagonals=selected_combined_covariance_diagonals,
        production_three_day_combined_predictions=short_combined,
        production_three_day_candidate_predictions=short_candidates,
        production_three_day_probabilities=short_probabilities,
        production_three_day_candidate_states=short_states,
        production_three_day_candidate_covariance_diagonals=short_covariance_diagonals,
        production_three_day_combined_states=short_combined_states,
        production_three_day_combined_covariance_diagonals=short_combined_covariance_diagonals,
        maximum_source_state_mutation=state_mutation,
        maximum_source_covariance_mutation=covariance_mutation,
        maximum_source_probability_mutation=probability_mutation,
    )
