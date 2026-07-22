"""Closed numerical validation of nine-candidate state interaction moments."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

import numpy as np

from hbv_joint_uncertainty.imm import interact_model_states


DEFAULT_STATE_SCALES = np.asarray(
    [100.0, 5.0, 200.0, 20.0, 100.0, *([5.0] * 10)], dtype=np.float64
)
INTERACTION_MODES = ("full", "parameter_grouped", "none")


@dataclass(frozen=True)
class StateInteractionValidationResult:
    trial_seeds: np.ndarray
    transition_matrix: np.ndarray
    parameter_groups: tuple[object, ...]
    state_scales: np.ndarray
    production_probabilities: np.ndarray
    production_states: np.ndarray
    production_covariances: np.ndarray
    production_conditional_weights: np.ndarray
    reference_probabilities: np.ndarray
    reference_states: np.ndarray
    reference_covariances: np.ndarray
    reference_conditional_weights: np.ndarray
    production_combined_means: np.ndarray
    production_combined_covariances: np.ndarray
    reference_combined_means: np.ndarray
    reference_combined_covariances: np.ndarray
    counterexample_modes: tuple[str, ...]
    counterexample_probabilities: np.ndarray
    counterexample_states: np.ndarray
    counterexample_covariances: np.ndarray
    counterexample_combined_means: np.ndarray
    counterexample_combined_covariances: np.ndarray


def _reference_interaction(
    states: np.ndarray,
    covariances: np.ndarray,
    transition: np.ndarray,
    probabilities: np.ndarray,
    groups: tuple[object, ...],
    mode: str,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    candidate_count, state_dimension = states.shape
    prior = transition.T @ probabilities
    prior = prior / prior.sum()
    weights = np.zeros((candidate_count, candidate_count), dtype=np.float64)
    mixed_states = states.copy()
    mixed_covariances = covariances.copy()
    if mode == "none":
        np.fill_diagonal(weights, 1.0)
        return prior, weights, mixed_states, mixed_covariances
    for destination in range(candidate_count):
        incoming = transition[:, destination] * probabilities
        if mode == "parameter_grouped":
            allowed = np.asarray(
                [group == groups[destination] for group in groups], dtype=bool
            )
            incoming = np.where(allowed, incoming, 0.0)
        total = float(incoming.sum())
        if total <= 0.0:
            weights[destination, destination] = 1.0
            continue
        conditional = incoming / total
        weights[destination] = conditional
        mean = np.zeros(state_dimension, dtype=np.float64)
        for source in range(candidate_count):
            mean += conditional[source] * states[source]
        covariance = np.zeros((state_dimension, state_dimension), dtype=np.float64)
        for source in range(candidate_count):
            difference = states[source] - mean
            covariance += conditional[source] * (
                covariances[source] + np.outer(difference, difference)
            )
        mixed_states[destination] = mean
        mixed_covariances[destination] = 0.5 * (covariance + covariance.T)
    return prior, weights, mixed_states, mixed_covariances


def _mixture_moments(
    probabilities: np.ndarray, states: np.ndarray, covariances: np.ndarray
) -> tuple[np.ndarray, np.ndarray]:
    state_dimension = states.shape[1]
    mean = np.zeros(state_dimension, dtype=np.float64)
    for probability, state in zip(probabilities, states):
        mean += probability * state
    covariance = np.zeros((state_dimension, state_dimension), dtype=np.float64)
    for probability, state, candidate_covariance in zip(
        probabilities, states, covariances
    ):
        difference = state - mean
        covariance += probability * (
            candidate_covariance + np.outer(difference, difference)
        )
    return mean, 0.5 * (covariance + covariance.T)


def _initial_trial(seed: int, state_scales: np.ndarray):
    probability_seed, state_seed, covariance_seed = np.random.SeedSequence(seed).spawn(3)
    probability_rng = np.random.default_rng(probability_seed)
    state_rng = np.random.default_rng(state_seed)
    covariance_rng = np.random.default_rng(covariance_seed)
    probabilities = probability_rng.dirichlet(np.linspace(0.8, 1.6, 9))
    states = state_scales[None, :] * state_rng.uniform(0.5, 1.5, size=(9, 15))
    covariances = np.empty((9, 15, 15), dtype=np.float64)
    for candidate in range(9):
        matrix = covariance_rng.normal(size=(15, 15)) * state_scales[None, :] * 0.01
        covariance = matrix.T @ matrix / 15.0
        covariance += np.diag(np.square(state_scales * 0.005))
        covariances[candidate] = 0.5 * (covariance + covariance.T)
    return probabilities, states, covariances


def _counterexample_initial_state():
    parameter_probabilities = np.asarray([0.8, 0.15, 0.05], dtype=np.float64)
    process_probabilities = np.asarray([0.1, 0.2, 0.7], dtype=np.float64)
    probabilities = np.outer(parameter_probabilities, process_probabilities).reshape(-1)
    states = np.zeros((9, 15), dtype=np.float64)
    states[:, 0] = np.repeat(np.asarray([0.0, 5.0, 10.0]), 3)
    states[:, 1] = np.tile(np.asarray([1.0, 2.0, 3.0]), 3)
    covariances = np.repeat(np.eye(15, dtype=np.float64)[None, :, :] * 0.01, 9, axis=0)
    return probabilities, states, covariances


def run_state_interaction_validation(
    trial_seeds: Sequence[int],
    steps: int,
    transition_matrix,
    parameter_groups: Sequence[object],
    state_scales=DEFAULT_STATE_SCALES,
) -> StateInteractionValidationResult:
    """Compare production full interaction with a separate direct moment calculation."""
    seeds = tuple(int(value) for value in trial_seeds)
    if not seeds or len(set(seeds)) != len(seeds):
        raise ValueError("trial_seeds must be nonempty and unique")
    if isinstance(steps, bool) or int(steps) != steps or int(steps) <= 0:
        raise ValueError("steps must be a positive integer")
    step_count = int(steps)
    transition = np.asarray(transition_matrix, dtype=np.float64)
    if transition.shape != (9, 9):
        raise ValueError("transition_matrix must have shape (9, 9)")
    if not np.all(np.isfinite(transition)) or np.any(transition < 0.0):
        raise ValueError("transition_matrix must be finite and nonnegative")
    if not np.allclose(transition.sum(axis=1), 1.0, rtol=0.0, atol=1e-12):
        raise ValueError("transition_matrix rows must sum to one")
    transition = transition / transition.sum(axis=1, keepdims=True)
    groups = tuple(parameter_groups)
    if len(groups) != 9 or any(group is None for group in groups):
        raise ValueError("parameter_groups must contain nine nonmissing labels")
    scales = np.asarray(state_scales, dtype=np.float64)
    if scales.shape != (15,) or not np.all(np.isfinite(scales)) or np.any(scales <= 0.0):
        raise ValueError("state_scales must contain fifteen finite positive values")

    trial_count = len(seeds)
    probability_shape = (trial_count, step_count + 1, 9)
    state_shape = (trial_count, step_count + 1, 9, 15)
    covariance_shape = (trial_count, step_count + 1, 9, 15, 15)
    weight_shape = (trial_count, step_count, 9, 9)
    combined_mean_shape = (trial_count, step_count + 1, 15)
    combined_covariance_shape = (trial_count, step_count + 1, 15, 15)
    production_probabilities = np.empty(probability_shape, dtype=np.float64)
    production_states = np.empty(state_shape, dtype=np.float64)
    production_covariances = np.empty(covariance_shape, dtype=np.float64)
    production_weights = np.empty(weight_shape, dtype=np.float64)
    reference_probabilities = np.empty(probability_shape, dtype=np.float64)
    reference_states = np.empty(state_shape, dtype=np.float64)
    reference_covariances = np.empty(covariance_shape, dtype=np.float64)
    reference_weights = np.empty(weight_shape, dtype=np.float64)
    production_means = np.empty(combined_mean_shape, dtype=np.float64)
    production_combined_covariances = np.empty(
        combined_covariance_shape, dtype=np.float64
    )
    reference_means = np.empty(combined_mean_shape, dtype=np.float64)
    reference_combined_covariances = np.empty(
        combined_covariance_shape, dtype=np.float64
    )

    for trial, seed in enumerate(seeds):
        probabilities, states, covariances = _initial_trial(seed, scales)
        production_probabilities[trial, 0] = probabilities
        production_states[trial, 0] = states
        production_covariances[trial, 0] = covariances
        reference_probabilities[trial, 0] = probabilities
        reference_states[trial, 0] = states
        reference_covariances[trial, 0] = covariances
        production_means[trial, 0], production_combined_covariances[trial, 0] = (
            _mixture_moments(probabilities, states, covariances)
        )
        reference_means[trial, 0] = production_means[trial, 0]
        reference_combined_covariances[trial, 0] = production_combined_covariances[
            trial, 0
        ]
        production_probability = probabilities.copy()
        production_state = states.copy()
        production_covariance = covariances.copy()
        reference_probability = probabilities.copy()
        reference_state = states.copy()
        reference_covariance = covariances.copy()
        for step in range(step_count):
            production = interact_model_states(
                states=production_state,
                covariances=production_covariance,
                transition_matrix=transition,
                current_probabilities=production_probability,
                parameter_groups=groups,
                interaction_mode="full",
            )
            reference = _reference_interaction(
                reference_state,
                reference_covariance,
                transition,
                reference_probability,
                groups,
                "full",
            )
            production_probability = production.prior_probabilities
            production_state = production.mixed_states
            production_covariance = production.mixed_covariances
            reference_probability, weights, reference_state, reference_covariance = reference
            production_probabilities[trial, step + 1] = production_probability
            production_states[trial, step + 1] = production_state
            production_covariances[trial, step + 1] = production_covariance
            production_weights[trial, step] = production.conditional_weights
            reference_probabilities[trial, step + 1] = reference_probability
            reference_states[trial, step + 1] = reference_state
            reference_covariances[trial, step + 1] = reference_covariance
            reference_weights[trial, step] = weights
            production_means[trial, step + 1], production_combined_covariances[
                trial, step + 1
            ] = _mixture_moments(
                production_probability, production_state, production_covariance
            )
            reference_means[trial, step + 1], reference_combined_covariances[
                trial, step + 1
            ] = _mixture_moments(
                reference_probability, reference_state, reference_covariance
            )

    counterexample_probability, counterexample_state, counterexample_covariance = (
        _counterexample_initial_state()
    )
    mode_count = len(INTERACTION_MODES)
    counterexample_probabilities = np.empty(
        (mode_count, step_count + 1, 9), dtype=np.float64
    )
    counterexample_states = np.empty(
        (mode_count, step_count + 1, 9, 15), dtype=np.float64
    )
    counterexample_covariances = np.empty(
        (mode_count, step_count + 1, 9, 15, 15), dtype=np.float64
    )
    counterexample_means = np.empty(
        (mode_count, step_count + 1, 15), dtype=np.float64
    )
    counterexample_combined_covariances = np.empty(
        (mode_count, step_count + 1, 15, 15), dtype=np.float64
    )
    for mode_index, mode in enumerate(INTERACTION_MODES):
        probabilities = counterexample_probability.copy()
        states = counterexample_state.copy()
        covariances = counterexample_covariance.copy()
        counterexample_probabilities[mode_index, 0] = probabilities
        counterexample_states[mode_index, 0] = states
        counterexample_covariances[mode_index, 0] = covariances
        counterexample_means[mode_index, 0], counterexample_combined_covariances[
            mode_index, 0
        ] = _mixture_moments(probabilities, states, covariances)
        for step in range(step_count):
            interaction = interact_model_states(
                states=states,
                covariances=covariances,
                transition_matrix=transition,
                current_probabilities=probabilities,
                parameter_groups=groups,
                interaction_mode=mode,
            )
            probabilities = interaction.prior_probabilities
            states = interaction.mixed_states
            covariances = interaction.mixed_covariances
            counterexample_probabilities[mode_index, step + 1] = probabilities
            counterexample_states[mode_index, step + 1] = states
            counterexample_covariances[mode_index, step + 1] = covariances
            counterexample_means[mode_index, step + 1], (
                counterexample_combined_covariances[mode_index, step + 1]
            ) = _mixture_moments(probabilities, states, covariances)

    return StateInteractionValidationResult(
        trial_seeds=np.asarray(seeds, dtype=np.int64),
        transition_matrix=transition.copy(),
        parameter_groups=groups,
        state_scales=scales.copy(),
        production_probabilities=production_probabilities,
        production_states=production_states,
        production_covariances=production_covariances,
        production_conditional_weights=production_weights,
        reference_probabilities=reference_probabilities,
        reference_states=reference_states,
        reference_covariances=reference_covariances,
        reference_conditional_weights=reference_weights,
        production_combined_means=production_means,
        production_combined_covariances=production_combined_covariances,
        reference_combined_means=reference_means,
        reference_combined_covariances=reference_combined_covariances,
        counterexample_modes=INTERACTION_MODES,
        counterexample_probabilities=counterexample_probabilities,
        counterexample_states=counterexample_states,
        counterexample_covariances=counterexample_covariances,
        counterexample_combined_means=counterexample_means,
        counterexample_combined_covariances=counterexample_combined_covariances,
    )
