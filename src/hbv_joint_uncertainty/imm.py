"""Parameter-conditioned interacting multiple-model estimation."""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Callable, Sequence

import numpy as np

from .sigma_filter import FilterStepResult, ModifiedUnscentedFilter


PairwiseMomentTransform = Callable[
    [int, int, np.ndarray, np.ndarray],
    tuple[np.ndarray, np.ndarray],
]
ModelEvidenceScorer = Callable[[FilterStepResult], float]


def _validated_degrees_of_freedom(value) -> float:
    degrees_of_freedom = float(value)
    if not np.isfinite(degrees_of_freedom) or degrees_of_freedom <= 0.0:
        raise ValueError("degrees of freedom must be finite and positive")
    return degrees_of_freedom


def student_t_log_model_evidence(
    innovation,
    innovation_scale,
    degrees_of_freedom,
) -> float:
    """Return multivariate Student-t log evidence using one scale matrix."""
    nu = _validated_degrees_of_freedom(degrees_of_freedom)
    residual = np.asarray(innovation, dtype=np.float64)
    scale = np.asarray(innovation_scale, dtype=np.float64)
    if residual.ndim != 1 or len(residual) == 0:
        raise ValueError("innovation must be a nonempty one-dimensional array")
    expected_shape = (len(residual), len(residual))
    if scale.shape != expected_shape:
        raise ValueError(f"innovation scale must have shape {expected_shape}")
    if not np.all(np.isfinite(residual)) or not np.all(np.isfinite(scale)):
        raise ValueError("innovation and innovation scale must be finite")
    if not np.allclose(scale, scale.T, rtol=0.0, atol=1e-12):
        raise ValueError("innovation scale must be symmetric")
    symmetric_scale = 0.5 * (scale + scale.T)
    try:
        cholesky = np.linalg.cholesky(symmetric_scale)
    except np.linalg.LinAlgError as error:
        raise ValueError("innovation scale must be positive definite") from error
    log_determinant = 2.0 * float(np.log(np.diag(cholesky)).sum())
    squared_distance = float(
        residual @ np.linalg.solve(symmetric_scale, residual)
    )
    if not np.isfinite(squared_distance) or squared_distance < 0.0:
        raise ValueError("innovation squared distance must be finite and nonnegative")
    dimension = len(residual)
    log_evidence = (
        math.lgamma((nu + dimension) / 2.0)
        - math.lgamma(nu / 2.0)
        - 0.5 * (log_determinant + dimension * math.log(nu * math.pi))
        - 0.5 * (nu + dimension) * math.log1p(squared_distance / nu)
    )
    if not np.isfinite(log_evidence):
        raise ValueError("Student-t model evidence must be finite")
    return float(log_evidence)


def student_t_model_evidence_scorer(
    degrees_of_freedom,
) -> ModelEvidenceScorer:
    """Build a scorer that changes model weights, not filter state updates."""
    nu = _validated_degrees_of_freedom(degrees_of_freedom)

    def score(result: FilterStepResult) -> float:
        return student_t_log_model_evidence(
            result.innovation,
            result.innovation_covariance,
            nu,
        )

    return score


def _model_log_evidence(
    result: FilterStepResult,
    scorer: ModelEvidenceScorer | None,
) -> float:
    value = result.log_likelihood if scorer is None else scorer(result)
    array = np.asarray(value, dtype=np.float64)
    if array.ndim != 0:
        raise ValueError("model evidence scorer must return one scalar")
    score = float(array)
    if not np.isfinite(score):
        raise ValueError("model evidence scorer must return one finite scalar")
    return score


def normalize_log_weights_with_logs(log_weights) -> tuple[np.ndarray, np.ndarray]:
    """Return normalized probabilities and their stable normalized logs."""
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
    log_normalizer = maximum + np.log(total)
    log_probabilities = np.full_like(values, -np.inf)
    log_probabilities[finite] = values[finite] - log_normalizer
    probabilities = np.zeros_like(values)
    probabilities[finite] = np.exp(log_probabilities[finite])
    probability_total = float(probabilities.sum())
    if not np.isfinite(probability_total) or probability_total <= 0.0:
        raise ValueError("normalized probabilities must contain positive mass")
    probabilities /= probability_total
    log_probabilities[finite] -= np.log(probability_total)
    return probabilities, log_probabilities


def normalize_log_weights(log_weights) -> np.ndarray:
    """Normalize log weights without exponential underflow."""
    probabilities, _ = normalize_log_weights_with_logs(log_weights)
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


def update_model_probabilities_with_logs(
    prior_probabilities,
    candidate_log_likelihoods,
) -> tuple[np.ndarray, np.ndarray]:
    """Apply likelihoods and retain stable normalized log probabilities."""
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
    return normalize_log_weights_with_logs(log_prior + likelihoods)


def update_model_probabilities(prior_probabilities, candidate_log_likelihoods) -> np.ndarray:
    """Apply one candidate log-likelihood vector to a predicted probability distribution."""
    probabilities, _ = update_model_probabilities_with_logs(
        prior_probabilities,
        candidate_log_likelihoods,
    )
    return probabilities


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
    pairwise_moment_transform: PairwiseMomentTransform | None = None,
) -> StateInteractionResult:
    """Condition candidate state moments on each destination model."""
    if interaction_mode not in {"full", "parameter_grouped", "none"}:
        raise ValueError("interaction_mode must be full, parameter_grouped, or none")
    if pairwise_moment_transform is not None and not callable(
        pairwise_moment_transform
    ):
        raise TypeError("pairwise_moment_transform must be callable or None")
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
        source_states = state_array
        source_covariances = covariance_array
        if pairwise_moment_transform is not None:
            source_states = state_array.copy()
            source_covariances = covariance_array.copy()
            for source, weight in enumerate(weights):
                if weight <= 0.0:
                    continue
                transformed = pairwise_moment_transform(
                    source,
                    destination,
                    state_array[source].copy(),
                    covariance_array[source].copy(),
                )
                if not isinstance(transformed, tuple) or len(transformed) != 2:
                    raise ValueError(
                        "pairwise_moment_transform must return (mean, covariance)"
                    )
                transformed_state = np.asarray(transformed[0], dtype=np.float64)
                transformed_covariance = np.asarray(
                    transformed[1],
                    dtype=np.float64,
                )
                if transformed_state.shape != (state_dimension,) or not np.all(
                    np.isfinite(transformed_state)
                ):
                    raise ValueError(
                        "pairwise_moment_transform returned an invalid state"
                    )
                if transformed_covariance.shape != (
                    state_dimension,
                    state_dimension,
                ) or not np.all(np.isfinite(transformed_covariance)):
                    raise ValueError(
                        "pairwise_moment_transform returned an invalid covariance"
                    )
                if not np.allclose(
                    transformed_covariance,
                    transformed_covariance.T,
                    rtol=0.0,
                    atol=1e-12,
                ):
                    raise ValueError(
                        "pairwise_moment_transform returned a nonsymmetric covariance"
                    )
                source_states[source] = transformed_state
                source_covariances[source] = 0.5 * (
                    transformed_covariance + transformed_covariance.T
                )
        mean = weights @ source_states
        covariance = np.zeros((state_dimension, state_dimension), dtype=np.float64)
        for weight, state, candidate_covariance in zip(
            weights, source_states, source_covariances
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
    posterior_log_probabilities: np.ndarray
    candidate_log_evidences: np.ndarray
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
        pairwise_moment_transform: PairwiseMomentTransform | None = None,
        model_evidence_scorer: ModelEvidenceScorer | None = None,
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
        if pairwise_moment_transform is not None and not callable(
            pairwise_moment_transform
        ):
            raise TypeError("pairwise_moment_transform must be callable or None")
        self.pairwise_moment_transform = pairwise_moment_transform
        if model_evidence_scorer is not None and not callable(
            model_evidence_scorer
        ):
            raise TypeError("model_evidence_scorer must be callable or None")
        self.model_evidence_scorer = model_evidence_scorer

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
            pairwise_moment_transform=self.pairwise_moment_transform,
        )
        for destination, candidate in enumerate(self.filters):
            candidate.state = interaction.mixed_states[destination].copy()
            candidate.covariance = interaction.mixed_covariances[destination].copy()
        return interaction.prior_probabilities.copy()

    def interact(self) -> np.ndarray:
        """Interact candidate moments and return destination-model priors."""
        return self._interact()

    def update_after_interaction(
        self,
        observation,
        prior_probabilities,
    ) -> InteractingStepResult:
        """Filter and combine after an explicit interaction operation."""
        prior_probabilities = np.asarray(prior_probabilities, dtype=np.float64)
        expected = (self.n_candidates,)
        if prior_probabilities.shape != expected:
            raise ValueError(
                f"prior_probabilities must have shape {expected}"
            )
        if not np.all(np.isfinite(prior_probabilities)) or np.any(
            prior_probabilities < 0.0
        ):
            raise ValueError("prior_probabilities must be finite and nonnegative")
        if not np.isclose(
            prior_probabilities.sum(), 1.0, rtol=0.0, atol=1e-12
        ):
            raise ValueError("prior_probabilities must sum to one")
        prior_probabilities = prior_probabilities / prior_probabilities.sum()
        candidate_results = tuple(candidate.step(observation) for candidate in self.filters)
        model_log_evidences = np.array(
            [
                _model_log_evidence(result, self.model_evidence_scorer)
                for result in candidate_results
            ],
            dtype=np.float64,
        )
        posterior_probabilities, posterior_log_probabilities = (
            update_model_probabilities_with_logs(
            prior_probabilities, model_log_evidences
            )
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
            posterior_log_probabilities=posterior_log_probabilities.copy(),
            candidate_log_evidences=model_log_evidences.copy(),
            candidate_results=candidate_results,
            combined_prior_observation=combined_prior_observation,
            combined_state=combined_state.copy(),
            combined_covariance=combined_covariance.copy(),
        )

    def step(self, observation) -> InteractingStepResult:
        prior_probabilities = self.interact()
        return self.update_after_interaction(observation, prior_probabilities)


@dataclass(frozen=True)
class PairwisePathStepResult:
    """One observation-postcollapse step with explicit source-destination paths."""

    prior_probabilities: np.ndarray
    posterior_probabilities: np.ndarray
    posterior_log_probabilities: np.ndarray
    branch_log_evidences: np.ndarray
    branch_prior_log_probabilities: np.ndarray
    branch_posterior_log_probabilities: np.ndarray
    branch_posterior_probabilities: np.ndarray
    destination_raw_probabilities: np.ndarray
    destination_raw_conditional_probabilities: np.ndarray
    destination_conditional_probabilities: np.ndarray
    branch_active_mask: np.ndarray
    destination_reference_indices: np.ndarray
    global_reference_index: int
    branch_results: tuple[tuple[FilterStepResult | None, ...], ...]
    destination_states: np.ndarray
    destination_covariances: np.ndarray
    combined_prior_observation: np.ndarray
    combined_state: np.ndarray
    combined_covariance: np.ndarray
    direct_state: np.ndarray
    direct_covariance: np.ndarray


def _logsumexp(values) -> float:
    """Return a stable scalar log-sum-exp while allowing inactive paths."""
    array = np.asarray(values, dtype=np.float64)
    if array.ndim != 1 or len(array) == 0:
        raise ValueError("log-sum-exp values must be a nonempty vector")
    if np.any(np.isnan(array)) or np.any(np.isposinf(array)):
        raise ValueError("log-sum-exp values cannot contain NaN or positive infinity")
    finite = np.isfinite(array)
    if not np.any(finite):
        return float("-inf")
    maximum = float(np.max(array[finite]))
    return float(maximum + np.log(np.exp(array[finite] - maximum).sum()))


def _mixture_moments(states, covariances, probabilities) -> tuple[np.ndarray, np.ndarray]:
    """Moment-match one finite Gaussian mixture."""
    state_array = np.asarray(states, dtype=np.float64)
    covariance_array = np.asarray(covariances, dtype=np.float64)
    weights = np.asarray(probabilities, dtype=np.float64)
    if state_array.ndim != 2 or state_array.shape[0] == 0:
        raise ValueError("mixture states must have shape (components, state dimensions)")
    component_count, state_dimension = state_array.shape
    if covariance_array.shape != (component_count, state_dimension, state_dimension):
        raise ValueError("mixture covariances have an incompatible shape")
    if weights.shape != (component_count,):
        raise ValueError("mixture probabilities have an incompatible shape")
    if not np.all(np.isfinite(state_array)) or not np.all(np.isfinite(covariance_array)):
        raise ValueError("mixture moments must be finite")
    if not np.all(np.isfinite(weights)) or np.any(weights < 0.0):
        raise ValueError("mixture probabilities must be finite and nonnegative")
    total = math.fsum(float(weight) for weight in weights)
    if not np.isfinite(total) or total <= 0.0:
        raise ValueError("mixture probabilities must contain positive mass")
    weights = weights / total
    mean = np.empty(state_dimension, dtype=np.float64)
    for index in range(state_dimension):
        mean[index] = math.fsum(
            float(weight * state[index])
            for weight, state in zip(weights, state_array)
        )
    covariance = np.zeros((state_dimension, state_dimension), dtype=np.float64)
    differences = state_array - mean
    for row in range(state_dimension):
        for column in range(state_dimension):
            covariance[row, column] = math.fsum(
                float(
                    weight
                    * (
                        component_covariance[row, column]
                        + difference[row] * difference[column]
                    )
                )
                for weight, difference, component_covariance in zip(
                    weights,
                    differences,
                    covariance_array,
                )
            )
    covariance = 0.5 * (covariance + covariance.T)
    if not np.all(np.isfinite(mean)) or not np.all(np.isfinite(covariance)):
        raise ValueError("mixture mean or covariance is non-finite")
    return mean, covariance


def _normalize_path_weights(weights) -> np.ndarray:
    """Normalize one nonnegative ordinary-weight vector with ``math.fsum``."""
    values = np.asarray(weights, dtype=np.float64)
    if values.ndim != 1 or len(values) == 0:
        raise ValueError("path weights must be a nonempty one-dimensional array")
    if not np.all(np.isfinite(values)) or np.any(values < 0.0):
        raise ValueError("path weights must be finite and nonnegative")
    total = math.fsum(float(value) for value in values)
    if not np.isfinite(total) or total <= 0.0:
        raise ValueError("path weights must contain positive mass")
    normalized = values / total
    if not np.all(np.isfinite(normalized)):
        raise ValueError("normalized path weights must be finite")
    return normalized


def _path_mixture_moments(
    states,
    covariances,
    probabilities,
) -> tuple[np.ndarray, np.ndarray, int]:
    """Moment-match a path mixture with the registered residual correction."""
    state_array = np.asarray(states, dtype=np.float64)
    covariance_array = np.asarray(covariances, dtype=np.float64)
    weights = np.asarray(probabilities, dtype=np.float64)
    if state_array.ndim != 2 or state_array.shape[0] == 0:
        raise ValueError("path mixture states must have shape (components, dimensions)")
    component_count, state_dimension = state_array.shape
    if covariance_array.shape != (component_count, state_dimension, state_dimension):
        raise ValueError("path mixture covariances have an incompatible shape")
    if weights.shape != (component_count,):
        raise ValueError("path mixture probabilities have an incompatible shape")
    if not np.all(np.isfinite(state_array)) or not np.all(
        np.isfinite(covariance_array)
    ):
        raise ValueError("path mixture moments must be finite")
    if not np.all(np.isfinite(weights)) or np.any(weights < 0.0):
        raise ValueError("path mixture probabilities must be finite and nonnegative")

    active_indices = np.flatnonzero(weights > 0.0)
    if len(active_indices) == 0:
        raise ValueError("path mixture probabilities must contain positive mass")
    active_weights = weights[active_indices]
    active_states = state_array[active_indices]
    active_covariances = covariance_array[active_indices]
    total = math.fsum(float(weight) for weight in active_weights)
    if not np.isfinite(total) or not 0.5 <= total <= 2.0:
        raise ValueError("path mixture probability sum must be between 0.5 and 2")

    local_reference_index = int(np.argmax(active_weights))
    reference_index = int(active_indices[local_reference_index])
    reference_state = active_states[local_reference_index]
    mean = np.empty(state_dimension, dtype=np.float64)
    for index in range(state_dimension):
        mean[index] = reference_state[index] + math.fsum(
            float(weight * (state[index] - reference_state[index]))
            for weight, state in zip(active_weights, active_states)
        ) / total

    covariance_raw = np.empty(
        (state_dimension, state_dimension),
        dtype=np.float64,
    )
    for row in range(state_dimension):
        for column in range(state_dimension):
            covariance_raw[row, column] = math.fsum(
                float(
                    weight
                    * (
                        component_covariance[row, column]
                        + (state[row] - mean[row])
                        * (state[column] - mean[column])
                    )
                )
                for weight, state, component_covariance in zip(
                    active_weights,
                    active_states,
                    active_covariances,
                )
            ) / total
    covariance = 0.5 * (covariance_raw + covariance_raw.T)
    if not np.all(np.isfinite(mean)) or not np.all(np.isfinite(covariance)):
        raise ValueError("path mixture mean or covariance is non-finite")
    return mean, covariance, reference_index


def _temporary_filter_from_template(
    template: ModifiedUnscentedFilter,
    state,
    covariance,
) -> ModifiedUnscentedFilter:
    """Create an isolated one-step filter with one destination model's settings."""
    sigma = template.sigma_generator
    return ModifiedUnscentedFilter(
        state=np.asarray(state, dtype=np.float64).copy(),
        covariance=np.asarray(covariance, dtype=np.float64).copy(),
        transition=template.transition,
        observation=template.observation,
        process_covariance=template.process_covariance.copy(),
        observation_covariance=template.observation_covariance.copy(),
        state_projector=template.state_projector,
        alpha=sigma.alpha,
        beta=sigma.beta,
        kappa=sigma.kappa,
    )


class PairwisePathMultipleModel:
    """Retain source-destination paths through observation, then collapse."""

    def __init__(
        self,
        filters: Sequence[ModifiedUnscentedFilter],
        transition_matrix,
        initial_probabilities,
        pairwise_moment_transform: PairwiseMomentTransform,
        model_evidence_scorer: ModelEvidenceScorer | None = None,
    ):
        self.filters = list(filters)
        if not self.filters:
            raise ValueError("filters must be nonempty")
        self.n_candidates = len(self.filters)
        dimensions = {candidate.n_state for candidate in self.filters}
        if len(dimensions) != 1:
            raise ValueError("all filters must use the same state dimension")
        observation_dimensions = {
            candidate.n_observation for candidate in self.filters
        }
        if len(observation_dimensions) != 1:
            raise ValueError("all filters must use the same observation dimension")
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
        self.log_transition_matrix = np.full(expected_shape, -np.inf, dtype=np.float64)
        positive_transitions = self.transition_matrix > 0.0
        self.log_transition_matrix[positive_transitions] = np.log(
            self.transition_matrix[positive_transitions]
        )

        probabilities = np.asarray(initial_probabilities, dtype=np.float64)
        if probabilities.shape != (self.n_candidates,):
            raise ValueError(
                f"initial_probabilities must have shape ({self.n_candidates},)"
            )
        if not np.all(np.isfinite(probabilities)) or np.any(probabilities < 0.0):
            raise ValueError("initial_probabilities must be finite and nonnegative")
        if not np.isclose(probabilities.sum(), 1.0, rtol=0.0, atol=1e-12):
            raise ValueError("initial_probabilities must sum to one")
        self.probabilities = probabilities / probabilities.sum()

        if not callable(pairwise_moment_transform):
            raise TypeError("pairwise_moment_transform must be callable")
        self.pairwise_moment_transform = pairwise_moment_transform
        if model_evidence_scorer is not None and not callable(
            model_evidence_scorer
        ):
            raise TypeError("model_evidence_scorer must be callable or None")
        self.model_evidence_scorer = model_evidence_scorer
        initial_states = np.asarray([candidate.state for candidate in self.filters])
        initial_covariances = np.asarray(
            [candidate.covariance for candidate in self.filters]
        )
        self.state, self.covariance = _mixture_moments(
            initial_states,
            initial_covariances,
            self.probabilities,
        )
        self.hypothesis_collapse_timing = "after_observation"

    def _branch_moments(
        self,
        source: int,
        destination: int,
    ) -> tuple[np.ndarray, np.ndarray]:
        source_filter = self.filters[source]
        state = source_filter.state.copy()
        covariance = source_filter.covariance.copy()
        if source == destination:
            return state, covariance
        transformed = self.pairwise_moment_transform(
            source,
            destination,
            state,
            covariance,
        )
        if not isinstance(transformed, tuple) or len(transformed) != 2:
            raise ValueError(
                "pairwise_moment_transform must return (mean, covariance)"
            )
        transformed_state = np.asarray(transformed[0], dtype=np.float64)
        transformed_covariance = np.asarray(transformed[1], dtype=np.float64)
        if transformed_state.shape != (self.n_state,) or not np.all(
            np.isfinite(transformed_state)
        ):
            raise ValueError("pairwise_moment_transform returned an invalid state")
        if transformed_covariance.shape != (
            self.n_state,
            self.n_state,
        ) or not np.all(np.isfinite(transformed_covariance)):
            raise ValueError(
                "pairwise_moment_transform returned an invalid covariance"
            )
        if not np.allclose(
            transformed_covariance,
            transformed_covariance.T,
            rtol=0.0,
            atol=1e-12,
        ):
            raise ValueError(
                "pairwise_moment_transform returned a nonsymmetric covariance"
            )
        return transformed_state.copy(), 0.5 * (
            transformed_covariance + transformed_covariance.T
        )

    def step(self, observation) -> PairwisePathStepResult:
        """Update every active transition path before destination collapse."""
        recursive_log_probabilities = np.full(
            self.n_candidates,
            -np.inf,
            dtype=np.float64,
        )
        positive_recursive_probabilities = self.probabilities > 0.0
        recursive_log_probabilities[positive_recursive_probabilities] = np.log(
            self.probabilities[positive_recursive_probabilities]
        )
        branch_log_prior = (
            recursive_log_probabilities[:, None] + self.log_transition_matrix
        )
        branch_prior_probabilities, _ = normalize_log_weights_with_logs(
            branch_log_prior.reshape(-1)
        )
        branch_prior_probabilities = branch_prior_probabilities.reshape(
            self.n_candidates,
            self.n_candidates,
        )
        prior_probabilities = branch_prior_probabilities.sum(axis=0)

        branch_results: list[list[FilterStepResult | None]] = [
            [None] * self.n_candidates for _ in range(self.n_candidates)
        ]
        branch_active_mask = np.zeros(
            (self.n_candidates, self.n_candidates),
            dtype=bool,
        )
        branch_log_posterior_unnormalized = np.full(
            (self.n_candidates, self.n_candidates),
            -np.inf,
            dtype=np.float64,
        )
        branch_log_evidences = np.full(
            (self.n_candidates, self.n_candidates),
            -np.inf,
            dtype=np.float64,
        )
        for source in range(self.n_candidates):
            for destination in range(self.n_candidates):
                if not np.isfinite(branch_log_prior[source, destination]):
                    continue
                state, covariance = self._branch_moments(source, destination)
                temporary_filter = _temporary_filter_from_template(
                    self.filters[destination],
                    state,
                    covariance,
                )
                result = temporary_filter.step(observation)
                branch_results[source][destination] = result
                branch_active_mask[source, destination] = True
                branch_log_evidences[source, destination] = _model_log_evidence(
                    result,
                    self.model_evidence_scorer,
                )
                branch_log_posterior_unnormalized[source, destination] = (
                    branch_log_prior[source, destination]
                    + branch_log_evidences[source, destination]
                )

        branch_posterior_probabilities, branch_log_posterior = (
            normalize_log_weights_with_logs(
                branch_log_posterior_unnormalized.reshape(-1)
            )
        )
        branch_posterior_probabilities = branch_posterior_probabilities.reshape(
            self.n_candidates,
            self.n_candidates,
        )
        branch_log_posterior = branch_log_posterior.reshape(
            self.n_candidates,
            self.n_candidates,
        )
        destination_log_weights = np.array(
            [
                _logsumexp(branch_log_posterior[:, destination])
                for destination in range(self.n_candidates)
            ],
            dtype=np.float64,
        )
        _, posterior_log_probabilities = normalize_log_weights_with_logs(
            destination_log_weights
        )
        destination_raw_probabilities = np.array(
            [
                math.fsum(
                    float(value)
                    for value in branch_posterior_probabilities[:, destination]
                )
                for destination in range(self.n_candidates)
            ],
            dtype=np.float64,
        )
        posterior_probabilities = _normalize_path_weights(
            destination_raw_probabilities
        )
        destination_raw_conditional_probabilities = np.zeros(
            (self.n_candidates, self.n_candidates),
            dtype=np.float64,
        )
        destination_conditional_probabilities = np.zeros(
            (self.n_candidates, self.n_candidates),
            dtype=np.float64,
        )

        destination_states = np.empty(
            (self.n_candidates, self.n_state),
            dtype=np.float64,
        )
        destination_covariances = np.empty(
            (self.n_candidates, self.n_state, self.n_state),
            dtype=np.float64,
        )
        destination_reference_indices = np.full(
            self.n_candidates,
            -1,
            dtype=np.int64,
        )
        for destination in range(self.n_candidates):
            raw_probability = destination_raw_probabilities[destination]
            if raw_probability <= 0.0:
                destination_states[destination] = self.filters[destination].state
                destination_covariances[destination] = (
                    self.filters[destination].covariance
                )
                continue
            raw_conditional_probabilities = (
                branch_posterior_probabilities[:, destination] / raw_probability
            )
            conditional_probabilities = _normalize_path_weights(
                raw_conditional_probabilities
            )
            destination_raw_conditional_probabilities[:, destination] = (
                raw_conditional_probabilities
            )
            destination_conditional_probabilities[:, destination] = (
                conditional_probabilities
            )
            active_states = []
            active_covariances = []
            active_probabilities = []
            active_sources = []
            for source, probability in enumerate(conditional_probabilities):
                branch_result = branch_results[source][destination]
                if probability <= 0.0:
                    continue
                if branch_result is None:
                    raise ValueError("positive path probability has no branch result")
                active_states.append(branch_result.posterior_state)
                active_covariances.append(branch_result.posterior_covariance)
                active_probabilities.append(probability)
                active_sources.append(source)
            state, covariance, local_reference_index = _path_mixture_moments(
                np.asarray(active_states),
                np.asarray(active_covariances),
                np.asarray(active_probabilities),
            )
            destination_states[destination] = state
            destination_covariances[destination] = covariance
            destination_reference_indices[destination] = active_sources[
                local_reference_index
            ]

        combined_state, combined_covariance, global_reference_index = (
            _path_mixture_moments(
            destination_states,
            destination_covariances,
            posterior_probabilities,
            )
        )
        direct_states = []
        direct_covariances = []
        direct_probabilities = []
        for source in range(self.n_candidates):
            for destination in range(self.n_candidates):
                probability = branch_posterior_probabilities[source, destination]
                branch_result = branch_results[source][destination]
                if probability <= 0.0 or branch_result is None:
                    continue
                direct_states.append(branch_result.posterior_state)
                direct_covariances.append(branch_result.posterior_covariance)
                direct_probabilities.append(probability)
        direct_state, direct_covariance, _ = _path_mixture_moments(
            np.asarray(direct_states),
            np.asarray(direct_covariances),
            np.asarray(direct_probabilities),
        )

        combined_prior_observation = None
        for source in range(self.n_candidates):
            for destination in range(self.n_candidates):
                probability = branch_prior_probabilities[source, destination]
                branch_result = branch_results[source][destination]
                if probability <= 0.0 or branch_result is None:
                    continue
                if combined_prior_observation is None:
                    combined_prior_observation = np.zeros_like(
                        branch_result.prior_observation
                    )
                combined_prior_observation += (
                    probability * branch_result.prior_observation
                )
        if combined_prior_observation is None:
            raise ValueError("no active branch produced a prior observation")

        for destination, candidate in enumerate(self.filters):
            candidate.state = destination_states[destination].copy()
            candidate.covariance = destination_covariances[destination].copy()
        self.probabilities = posterior_probabilities.copy()
        self.state = combined_state.copy()
        self.covariance = combined_covariance.copy()
        frozen_branch_results = tuple(
            tuple(row) for row in branch_results
        )
        return PairwisePathStepResult(
            prior_probabilities=prior_probabilities.copy(),
            posterior_probabilities=posterior_probabilities.copy(),
            posterior_log_probabilities=posterior_log_probabilities.copy(),
            branch_log_evidences=branch_log_evidences.copy(),
            branch_prior_log_probabilities=branch_log_prior.copy(),
            branch_posterior_log_probabilities=branch_log_posterior.copy(),
            branch_posterior_probabilities=(
                branch_posterior_probabilities.copy()
            ),
            destination_raw_probabilities=(
                destination_raw_probabilities.copy()
            ),
            destination_raw_conditional_probabilities=(
                destination_raw_conditional_probabilities.copy()
            ),
            destination_conditional_probabilities=(
                destination_conditional_probabilities.copy()
            ),
            branch_active_mask=branch_active_mask.copy(),
            destination_reference_indices=(
                destination_reference_indices.copy()
            ),
            global_reference_index=global_reference_index,
            branch_results=frozen_branch_results,
            destination_states=destination_states.copy(),
            destination_covariances=destination_covariances.copy(),
            combined_prior_observation=combined_prior_observation.copy(),
            combined_state=combined_state.copy(),
            combined_covariance=combined_covariance.copy(),
            direct_state=direct_state.copy(),
            direct_covariance=direct_covariance.copy(),
        )
