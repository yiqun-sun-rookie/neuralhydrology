"""Parameter-conditioned interacting multiple-model estimation."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

import numpy as np

from .sigma_filter import FilterStepResult, ModifiedUnscentedFilter


def normalize_log_weights(log_weights) -> np.ndarray:
    """Normalize log weights without exponential underflow."""
    values = np.asarray(log_weights, dtype=np.float64)
    if values.ndim != 1 or len(values) == 0:
        raise ValueError("log_weights must be a nonempty one-dimensional array")
    if np.any(np.isnan(values)) or np.any(np.isposinf(values)):
        raise ValueError("log_weights cannot contain NaN or positive infinity")
    finite = np.isfinite(values)
    if not np.any(finite):
        raise ValueError("at least one log weight must be finite")
    shifted = np.zeros_like(values)
    maximum = np.max(values[finite])
    shifted[finite] = np.exp(values[finite] - maximum)
    total = float(np.sum(shifted))
    if not np.isfinite(total) or total <= 0.0:
        raise ValueError("log weights could not be normalized")
    probabilities = shifted / total
    probabilities /= probabilities.sum()
    return probabilities


def predict_model_probabilities(transition_matrix, current_probabilities) -> np.ndarray:
    """Advance one finite candidate probability distribution through a row transition matrix."""
    probabilities = np.asarray(current_probabilities, dtype=np.float64)
    if probabilities.ndim != 1 or len(probabilities) == 0:
        raise ValueError("current_probabilities must be a nonempty one-dimensional array")
    if not np.all(np.isfinite(probabilities)) or np.any(probabilities < 0.0):
        raise ValueError("current_probabilities must be finite and nonnegative")
    if not np.isclose(probabilities.sum(), 1.0, rtol=0.0, atol=1e-12):
        raise ValueError("current_probabilities must sum to one")
    probabilities = probabilities / probabilities.sum()
    matrix = np.asarray(transition_matrix, dtype=np.float64)
    expected = (len(probabilities), len(probabilities))
    if matrix.shape != expected:
        raise ValueError(f"transition_matrix must have shape {expected}")
    if not np.all(np.isfinite(matrix)) or np.any(matrix < 0.0):
        raise ValueError("transition_matrix must be finite and nonnegative")
    if not np.allclose(matrix.sum(axis=1), 1.0, rtol=0.0, atol=1e-12):
        raise ValueError("transition_matrix rows must sum to one")
    matrix = matrix / matrix.sum(axis=1, keepdims=True)
    predicted = matrix.T @ probabilities
    if not np.all(np.isfinite(predicted)) or np.any(predicted < 0.0):
        raise ValueError("predicted probabilities must be finite and nonnegative")
    total = float(predicted.sum())
    if total <= 0.0:
        raise ValueError("predicted probabilities must contain positive mass")
    predicted /= total
    return predicted


def update_model_probabilities(prior_probabilities, candidate_log_likelihoods) -> np.ndarray:
    """Apply one candidate log-likelihood vector to a predicted probability distribution."""
    prior = np.asarray(prior_probabilities, dtype=np.float64)
    likelihoods = np.asarray(candidate_log_likelihoods, dtype=np.float64)
    if prior.ndim != 1 or len(prior) == 0 or likelihoods.shape != prior.shape:
        raise ValueError("prior probabilities and log likelihoods must be equal nonempty vectors")
    if not np.all(np.isfinite(prior)) or np.any(prior < 0.0):
        raise ValueError("prior probabilities must be finite and nonnegative")
    if not np.isclose(prior.sum(), 1.0, rtol=0.0, atol=1e-12):
        raise ValueError("prior probabilities must sum to one")
    if np.any(np.isnan(likelihoods)) or np.any(np.isposinf(likelihoods)):
        raise ValueError("candidate log likelihoods cannot contain NaN or positive infinity")
    prior = prior / prior.sum()
    log_prior = np.full(len(prior), -np.inf, dtype=np.float64)
    positive = prior > 0.0
    log_prior[positive] = np.log(prior[positive])
    return normalize_log_weights(log_prior + likelihoods)


@dataclass(frozen=True)
class StateInteractionResult:
    prior_probabilities: np.ndarray
    conditional_weights: np.ndarray
    mixed_states: np.ndarray
    mixed_covariances: np.ndarray


def interact_model_states(
    states,
    covariances,
    transition_matrix,
    current_probabilities,
    parameter_groups: Sequence[object],
    interaction_mode: str = "full",
) -> StateInteractionResult:
    """Condition candidate state moments on each destination model."""
    if interaction_mode not in {"full", "parameter_grouped", "none"}:
        raise ValueError("interaction_mode must be full, parameter_grouped, or none")
    state_array = np.asarray(states, dtype=np.float64)
    covariance_array = np.asarray(covariances, dtype=np.float64)
    probabilities = np.asarray(current_probabilities, dtype=np.float64)
    if state_array.ndim != 2 or state_array.shape[0] == 0:
        raise ValueError("states must have shape (candidates, state dimensions)")
    candidate_count, state_dimension = state_array.shape
    if probabilities.shape != (candidate_count,):
        raise ValueError(f"current_probabilities must have shape ({candidate_count},)")
    expected_covariance_shape = (candidate_count, state_dimension, state_dimension)
    if covariance_array.shape != expected_covariance_shape:
        raise ValueError(f"covariances must have shape {expected_covariance_shape}")
    if not np.all(np.isfinite(state_array)) or not np.all(np.isfinite(covariance_array)):
        raise ValueError("states and covariances must be finite")
    if not np.allclose(
        covariance_array,
        np.swapaxes(covariance_array, 1, 2),
        rtol=0.0,
        atol=1e-12,
    ):
        raise ValueError("candidate covariances must be symmetric")
    groups = tuple(parameter_groups)
    if len(groups) != candidate_count:
        raise ValueError(f"parameter_groups must contain {candidate_count} labels")
    if interaction_mode == "parameter_grouped" and any(group is None for group in groups):
        raise ValueError("parameter_groups cannot contain missing labels")

    matrix = np.asarray(transition_matrix, dtype=np.float64)
    prior_probabilities = predict_model_probabilities(matrix, probabilities)
    conditional_weights = np.zeros((candidate_count, candidate_count), dtype=np.float64)
    mixed_states = state_array.copy()
    mixed_covariances = covariance_array.copy()
    if interaction_mode == "none":
        np.fill_diagonal(conditional_weights, 1.0)
        return StateInteractionResult(
            prior_probabilities=prior_probabilities,
            conditional_weights=conditional_weights,
            mixed_states=mixed_states,
            mixed_covariances=mixed_covariances,
        )

    for destination in range(candidate_count):
        incoming = matrix[:, destination] * probabilities
        if interaction_mode == "parameter_grouped":
            permitted = np.asarray(
                [group == groups[destination] for group in groups], dtype=bool
            )
            incoming = np.where(permitted, incoming, 0.0)
        total = float(incoming.sum())
        if total <= 0.0:
            conditional_weights[destination, destination] = 1.0
            continue
        weights = incoming / total
        conditional_weights[destination] = weights
        mean = weights @ state_array
        covariance = np.zeros((state_dimension, state_dimension), dtype=np.float64)
        for weight, state, candidate_covariance in zip(
            weights, state_array, covariance_array
        ):
            difference = state - mean
            covariance += weight * (
                candidate_covariance + np.outer(difference, difference)
            )
        mixed_states[destination] = mean
        mixed_covariances[destination] = 0.5 * (covariance + covariance.T)
    return StateInteractionResult(
        prior_probabilities=prior_probabilities,
        conditional_weights=conditional_weights,
        mixed_states=mixed_states,
        mixed_covariances=mixed_covariances,
    )


@dataclass(frozen=True)
class InteractingStepResult:
    prior_probabilities: np.ndarray
    posterior_probabilities: np.ndarray
    candidate_results: tuple[FilterStepResult, ...]
    combined_prior_observation: np.ndarray
    combined_state: np.ndarray
    combined_covariance: np.ndarray


class InteractingMultipleModel:
    """Run full, parameter_grouped, or none interaction; the legacy default is parameter_grouped."""

    def __init__(
        self,
        filters: Sequence[ModifiedUnscentedFilter],
        transition_matrix,
        initial_probabilities,
        parameter_groups: Sequence[object],
    ):
        self.filters = list(filters)
        if not self.filters:
            raise ValueError("filters must be nonempty")
        self.n_candidates = len(self.filters)
        dimensions = {candidate.n_state for candidate in self.filters}
        if len(dimensions) != 1:
            raise ValueError("all filters must use the same state dimension")
        self.n_state = dimensions.pop()

        matrix = np.asarray(transition_matrix, dtype=np.float64)
        expected_shape = (self.n_candidates, self.n_candidates)
        if matrix.shape != expected_shape:
            raise ValueError(f"transition_matrix must have shape {expected_shape}")
        if not np.all(np.isfinite(matrix)) or np.any(matrix < 0.0):
            raise ValueError("transition_matrix must be finite and nonnegative")
        if not np.allclose(matrix.sum(axis=1), 1.0, rtol=0.0, atol=1e-12):
            raise ValueError("transition_matrix rows must sum to one")
        self.transition_matrix = matrix / matrix.sum(axis=1, keepdims=True)

        probabilities = np.asarray(initial_probabilities, dtype=np.float64)
        if probabilities.shape != (self.n_candidates,):
            raise ValueError(f"initial_probabilities must have shape ({self.n_candidates},)")
        if not np.all(np.isfinite(probabilities)) or np.any(probabilities < 0.0):
            raise ValueError("initial_probabilities must be finite and nonnegative")
        if not np.isclose(probabilities.sum(), 1.0, rtol=0.0, atol=1e-12):
            raise ValueError("initial_probabilities must sum to one")
        self.probabilities = probabilities / probabilities.sum()

        groups = tuple(parameter_groups)
        if len(groups) != self.n_candidates:
            raise ValueError(f"parameter_groups must contain {self.n_candidates} labels")
        if any(group is None for group in groups):
            raise ValueError("parameter_groups cannot contain missing labels")
        self.parameter_groups = groups

        self.state = self.filters[0].state.copy()
        self.covariance = self.filters[0].covariance.copy()

    def _interact(self) -> np.ndarray:
        interaction = interact_model_states(
            states=np.asarray([candidate.state for candidate in self.filters]),
            covariances=np.asarray(
                [candidate.covariance for candidate in self.filters]
            ),
            transition_matrix=self.transition_matrix,
            current_probabilities=self.probabilities,
            parameter_groups=self.parameter_groups,
            interaction_mode=getattr(self, "interaction_mode", "parameter_grouped"),
        )
        for destination, candidate in enumerate(self.filters):
            candidate.state = interaction.mixed_states[destination].copy()
            candidate.covariance = interaction.mixed_covariances[destination].copy()
        return interaction.prior_probabilities.copy()

    def step(self, observation) -> InteractingStepResult:
        prior_probabilities = self._interact()
        candidate_results = tuple(candidate.step(observation) for candidate in self.filters)
        log_likelihoods = np.array([result.log_likelihood for result in candidate_results], dtype=np.float64)
        posterior_probabilities = update_model_probabilities(
            prior_probabilities, log_likelihoods
        )

        combined_prior_observation = np.zeros_like(candidate_results[0].prior_observation)
        for probability, result in zip(prior_probabilities, candidate_results):
            combined_prior_observation += probability * result.prior_observation

        combined_state = np.zeros(self.n_state, dtype=np.float64)
        for probability, result in zip(posterior_probabilities, candidate_results):
            combined_state += probability * result.posterior_state
        combined_covariance = np.zeros((self.n_state, self.n_state), dtype=np.float64)
        for probability, result in zip(posterior_probabilities, candidate_results):
            deviation = result.posterior_state - combined_state
            combined_covariance += probability * (
                result.posterior_covariance + np.outer(deviation, deviation)
            )
        combined_covariance = 0.5 * (combined_covariance + combined_covariance.T)
        if not np.all(np.isfinite(combined_state)) or not np.all(np.isfinite(combined_covariance)):
            raise ValueError("combined state or covariance is non-finite")
        if abs(float(posterior_probabilities.sum()) - 1.0) > 1e-12:
            raise ValueError("posterior probabilities do not sum to one within 1e-12")

        self.probabilities = posterior_probabilities
        self.state = combined_state
        self.covariance = combined_covariance
        return InteractingStepResult(
            prior_probabilities=prior_probabilities.copy(),
            posterior_probabilities=posterior_probabilities.copy(),
            candidate_results=candidate_results,
            combined_prior_observation=combined_prior_observation,
            combined_state=combined_state.copy(),
            combined_covariance=combined_covariance.copy(),
        )
