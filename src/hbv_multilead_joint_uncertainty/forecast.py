"""Causal one-, three-, and seven-day forecasts from copied posterior filter banks."""

from __future__ import annotations

import copy
from dataclasses import dataclass
from collections.abc import Callable
from typing import Sequence

import numpy as np

from hbv_joint_uncertainty.preflight import CandidateBank
from hbv_joint_uncertainty.imm import interact_model_states, normalize_log_weights
from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter, unscented_transform


@dataclass(frozen=True)
class PosteriorForecast:
    lead_days: np.ndarray
    combined_predictions: np.ndarray
    candidate_predictions: np.ndarray
    probabilities: np.ndarray
    candidate_states: np.ndarray
    candidate_covariance_diagonals: np.ndarray
    combined_states: np.ndarray
    combined_covariance_diagonals: np.ndarray


@dataclass(frozen=True)
class MultiLeadAssimilationResult:
    lead_days: np.ndarray
    origin_indices: np.ndarray
    target_indices: np.ndarray
    predictions: np.ndarray
    candidate_predictions: np.ndarray
    probabilities: np.ndarray
    candidate_covariance_diagonals: np.ndarray
    combined_covariance_diagonals: np.ndarray


def _validated_leads(lead_days: Sequence[int], n_days: int) -> np.ndarray:
    if isinstance(n_days, bool) or int(n_days) != n_days or int(n_days) <= 1:
        raise ValueError("n_days must be an integer greater than one")
    leads = tuple(lead_days)
    if not leads:
        raise ValueError("lead_days must be nonempty")
    if any(isinstance(value, bool) or not isinstance(value, (int, np.integer)) for value in leads):
        raise ValueError("lead_days must contain integers")
    values = np.asarray(leads, dtype=np.int64)
    if np.any(values <= 0) or np.any(np.diff(values) <= 0):
        raise ValueError("lead_days must be positive, unique, and strictly increasing")
    if int(values[-1]) >= int(n_days):
        raise ValueError("the maximum lead must leave at least one common forecast origin")
    return values


def origin_target_indices(n_days: int, lead_days: Sequence[int] = (1, 3, 7)) -> tuple[np.ndarray, np.ndarray]:
    """Return common origin indices and their target indices for every lead."""
    leads = _validated_leads(lead_days, n_days)
    origins = np.arange(int(n_days) - int(leads[-1]), dtype=np.int64)
    targets = origins[:, None] + leads[None, :]
    return origins, targets


def _predicted_observation(candidate: ModifiedUnscentedFilter, state: np.ndarray, covariance: np.ndarray) -> np.ndarray:
    sigmas = candidate.sigma_generator.sigma_points(state, covariance)
    observation_sigmas = np.asarray([candidate.observation(point.copy()) for point in sigmas], dtype=np.float64)
    if observation_sigmas.shape == (len(sigmas),):
        observation_sigmas = observation_sigmas[:, None]
    expected = (len(sigmas), candidate.n_observation)
    if observation_sigmas.shape != expected or not np.all(np.isfinite(observation_sigmas)):
        raise ValueError(f"observation function returned {observation_sigmas.shape}; expected {expected}")
    mean, _ = unscented_transform(
        observation_sigmas,
        candidate.sigma_generator.mean_weights,
        candidate.sigma_generator.covariance_weights,
        candidate.observation_covariance,
    )
    return mean


def _assert_posterior_ready(bank: CandidateBank) -> None:
    pending = [
        index
        for index, candidate in enumerate(bank.estimator.filters)
        if candidate._prior_state is not None or candidate._prior_covariance is not None
    ]
    if pending:
        raise RuntimeError(f"forecast requires posterior filters; candidates with an unupdated prior: {pending}")


def _interact_for_forecast(estimator, interaction_mode: str) -> np.ndarray:
    interaction = interact_model_states(
        states=np.asarray([candidate.state for candidate in estimator.filters]),
        covariances=np.asarray(
            [candidate.covariance for candidate in estimator.filters]
        ),
        transition_matrix=estimator.transition_matrix,
        current_probabilities=estimator.probabilities,
        parameter_groups=estimator.parameter_groups,
        interaction_mode=interaction_mode,
    )
    for destination, candidate in enumerate(estimator.filters):
        candidate.state = interaction.mixed_states[destination].copy()
        candidate.covariance = interaction.mixed_covariances[destination].copy()
    return interaction.prior_probabilities.copy()


def _combined_state_and_covariance(estimator, probabilities, states, covariances):
    state_matrix = np.asarray(states, dtype=np.float64)
    combined_state = probabilities @ state_matrix
    combined_covariance = np.zeros((estimator.n_state, estimator.n_state), dtype=np.float64)
    for probability, state, covariance in zip(probabilities, states, covariances):
        difference = state - combined_state
        combined_covariance += probability * (covariance + np.outer(difference, difference))
    return combined_state, 0.5 * (combined_covariance + combined_covariance.T)


def _forecast_one_day(bank: CandidateBank, interaction_mode: str):
    estimator = bank.estimator
    probabilities = _interact_for_forecast(estimator, interaction_mode)
    candidate_observations = []
    predicted_states = []
    predicted_covariances = []
    for candidate in estimator.filters:
        state, covariance = candidate.predict()
        candidate_observations.append(_predicted_observation(candidate, state, covariance))
        candidate.state = state.copy()
        candidate.covariance = covariance.copy()
        candidate._prior_state = None
        candidate._prior_covariance = None
        predicted_states.append(state)
        predicted_covariances.append(covariance)

    observation_matrix = np.asarray(candidate_observations, dtype=np.float64)
    combined_observation = probabilities @ observation_matrix
    combined_state, combined_covariance = _combined_state_and_covariance(
        estimator, probabilities, predicted_states, predicted_covariances
    )
    estimator.probabilities = probabilities.copy()
    estimator.state = combined_state.copy()
    estimator.covariance = 0.5 * (combined_covariance + combined_covariance.T)
    return (
        combined_observation,
        observation_matrix,
        np.asarray(predicted_states, dtype=np.float64),
        np.asarray([np.diag(value) for value in predicted_covariances], dtype=np.float64),
        combined_state,
        np.diag(combined_covariance).copy(),
    )


def _assimilation_step(bank: CandidateBank, observation: float, interaction_mode: str) -> tuple[float, float]:
    estimator = bank.estimator
    prior_probabilities = _interact_for_forecast(estimator, interaction_mode)
    results = tuple(candidate.step(observation) for candidate in estimator.filters)
    log_prior = np.full(len(prior_probabilities), -np.inf, dtype=np.float64)
    positive = prior_probabilities > 0.0
    log_prior[positive] = np.log(prior_probabilities[positive])
    log_joint = log_prior + np.asarray([result.log_likelihood for result in results], dtype=np.float64)
    posterior_probabilities = normalize_log_weights(log_joint)
    finite = np.isfinite(log_joint)
    maximum = float(np.max(log_joint[finite]))
    mixture_log_likelihood = maximum + float(np.log(np.sum(np.exp(log_joint[finite] - maximum))))
    states = [result.posterior_state for result in results]
    covariances = [result.posterior_covariance for result in results]
    combined_state, combined_covariance = _combined_state_and_covariance(
        estimator, posterior_probabilities, states, covariances
    )
    estimator.probabilities = posterior_probabilities
    estimator.state = combined_state.copy()
    estimator.covariance = combined_covariance.copy()
    combined_prior_observation = float(
        sum(
            probability * result.prior_observation[0]
            for probability, result in zip(prior_probabilities, results)
        )
    )
    return mixture_log_likelihood, combined_prior_observation


def forecast_from_posterior(
    bank: CandidateBank,
    future_forcing,
    lead_days: Sequence[int] = (1, 3, 7),
    interaction_mode: str | None = None,
    forecast_transition: str = "markov",
) -> PosteriorForecast:
    """Forecast from a posterior bank copy without reading or updating future discharge.

    ``forecast_transition`` controls whether the model-switching matrix P acts during
    the forecast horizon. ``"markov"`` (default) propagates the model probabilities and
    conditional state mixing through P each forecast day, reproducing the historical
    drifting behaviour. ``"frozen"`` holds the forecast transition at the identity
    matrix, which freezes the model probabilities at the final assimilation posterior
    and removes forecast-phase state mixing for every interaction mode -- i.e. P is not
    applied during the forecast. The assimilation state carried in ``bank`` is untouched.
    """
    if forecast_transition not in {"markov", "frozen"}:
        raise ValueError("forecast_transition must be 'markov' or 'frozen'")
    forcing = np.asarray(future_forcing, dtype=np.float64)
    if forcing.ndim != 2 or forcing.shape[1] != 3 or not np.all(np.isfinite(forcing)):
        raise ValueError("future_forcing must be a finite array with shape (days, 3)")
    leads = _validated_leads(lead_days, len(forcing) + 1)
    if len(forcing) < int(leads[-1]):
        raise ValueError("future_forcing does not cover the maximum lead")
    _assert_posterior_ready(bank)
    branch = copy.deepcopy(bank)
    n_candidates = len(branch.estimator.filters)
    if len(branch.transitions) != n_candidates or len(branch.definitions) != n_candidates:
        raise ValueError("candidate bank components must have identical candidate counts")
    if forecast_transition == "frozen":
        branch.estimator.transition_matrix = np.eye(n_candidates, dtype=np.float64)
    mode = interaction_mode or getattr(branch.estimator, "interaction_mode", "full")

    combined = np.empty(len(leads), dtype=np.float64)
    candidate_values = np.empty((len(leads), n_candidates), dtype=np.float64)
    probabilities = np.empty((len(leads), n_candidates), dtype=np.float64)
    state_count = branch.estimator.n_state
    candidate_states = np.empty((len(leads), n_candidates, state_count), dtype=np.float64)
    candidate_covariance_diagonals = np.empty_like(candidate_states)
    combined_states = np.empty((len(leads), state_count), dtype=np.float64)
    combined_covariance_diagonals = np.empty_like(combined_states)
    lead_to_row = {int(lead): row for row, lead in enumerate(leads)}
    for step in range(1, int(leads[-1]) + 1):
        rain, pet, temperature = forcing[step - 1]
        for transition in branch.transitions:
            transition.set_forcing(rain, pet, temperature)
        (
            combined_observation,
            candidate_observations,
            step_states,
            step_covariance_diagonals,
            step_combined_state,
            step_combined_covariance_diagonal,
        ) = _forecast_one_day(branch, mode)
        if step in lead_to_row:
            row = lead_to_row[step]
            if combined_observation.shape != (1,) or candidate_observations.shape != (n_candidates, 1):
                raise ValueError("multi-lead discharge forecasts require one scalar observation per candidate")
            combined[row] = combined_observation[0]
            candidate_values[row] = candidate_observations[:, 0]
            probabilities[row] = branch.estimator.probabilities
            candidate_states[row] = step_states
            candidate_covariance_diagonals[row] = step_covariance_diagonals
            combined_states[row] = step_combined_state
            combined_covariance_diagonals[row] = step_combined_covariance_diagonal

    if not np.all(np.isfinite(combined)) or not np.all(np.isfinite(candidate_values)):
        raise ValueError("forecast result contains non-finite values")
    if np.max(np.abs(probabilities.sum(axis=1) - 1.0), initial=0.0) > 1e-12:
        raise ValueError("forecast probabilities do not sum to one within 1e-12")
    return PosteriorForecast(
        lead_days=leads.copy(),
        combined_predictions=combined,
        candidate_predictions=candidate_values,
        probabilities=probabilities,
        candidate_states=candidate_states,
        candidate_covariance_diagonals=candidate_covariance_diagonals,
        combined_states=combined_states,
        combined_covariance_diagonals=combined_covariance_diagonals,
    )


def run_multilead_assimilation(
    forcing,
    observations,
    bank: CandidateBank,
    lead_days: Sequence[int] = (1, 3, 7),
    interaction_mode: str | None = None,
    progress_callback: Callable[[int, int], None] | None = None,
) -> MultiLeadAssimilationResult:
    """Assimilate through each origin and issue immutable forecasts from its posterior state."""
    forcing_values = np.asarray(forcing, dtype=np.float64)
    observed_values = np.asarray(observations, dtype=np.float64)
    if forcing_values.ndim != 2 or forcing_values.shape[1] != 3:
        raise ValueError("forcing must have shape (days, 3)")
    if observed_values.shape != (len(forcing_values),):
        raise ValueError("observations must have one value per forcing day")
    origins, targets = origin_target_indices(len(forcing_values), lead_days)
    if not np.all(np.isfinite(forcing_values)):
        raise ValueError("forcing must be finite")
    if not np.all(np.isfinite(observed_values[origins])):
        raise ValueError("discharge must be finite on every assimilation origin")
    leads = np.asarray(tuple(lead_days), dtype=np.int64)
    continuing = copy.deepcopy(bank)
    _assert_posterior_ready(continuing)
    mode = interaction_mode or getattr(continuing.estimator, "interaction_mode", "full")
    predictions = np.empty((len(origins), len(leads)), dtype=np.float64)
    candidate_count = len(continuing.estimator.filters)
    state_count = continuing.estimator.n_state
    candidate_predictions = np.empty((len(origins), len(leads), candidate_count), dtype=np.float64)
    probabilities = np.empty_like(candidate_predictions)
    candidate_covariance_diagonals = np.empty(
        (len(origins), len(leads), candidate_count, state_count), dtype=np.float64
    )
    combined_covariance_diagonals = np.empty((len(origins), len(leads), state_count), dtype=np.float64)
    maximum_lead = int(leads[-1])
    for row, origin in enumerate(origins):
        rain, pet, temperature = forcing_values[origin]
        for transition in continuing.transitions:
            transition.set_forcing(rain, pet, temperature)
        _assimilation_step(continuing, observed_values[origin], mode)
        future = forcing_values[origin + 1:origin + maximum_lead + 1]
        forecast = forecast_from_posterior(continuing, future, lead_days=leads, interaction_mode=mode)
        predictions[row] = forecast.combined_predictions
        candidate_predictions[row] = forecast.candidate_predictions
        probabilities[row] = forecast.probabilities
        candidate_covariance_diagonals[row] = forecast.candidate_covariance_diagonals
        combined_covariance_diagonals[row] = forecast.combined_covariance_diagonals
        if progress_callback is not None:
            progress_callback(row + 1, len(origins))

    return MultiLeadAssimilationResult(
        lead_days=leads.copy(),
        origin_indices=origins,
        target_indices=targets,
        predictions=predictions,
        candidate_predictions=candidate_predictions,
        probabilities=probabilities,
        candidate_covariance_diagonals=candidate_covariance_diagonals,
        combined_covariance_diagonals=combined_covariance_diagonals,
    )
