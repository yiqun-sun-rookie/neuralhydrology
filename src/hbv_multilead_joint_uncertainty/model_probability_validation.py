"""Closed synthetic validation of nine-candidate probability recursion."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

import numpy as np

from hbv_joint_uncertainty.imm import (
    predict_model_probabilities,
    update_model_probabilities,
)


@dataclass(frozen=True)
class ModelProbabilityValidationResult:
    trial_seeds: np.ndarray
    parameter_ids: tuple[str, str, str]
    process_ids: tuple[str, str, str]
    candidate_factors: tuple[tuple[str, str], ...]
    candidate_parameter_indices: np.ndarray
    candidate_process_indices: np.ndarray
    transition_matrix: np.ndarray
    transition_uniforms: np.ndarray
    emission_standard_normals: np.ndarray
    true_candidate_indices: np.ndarray
    observations: np.ndarray
    parameter_log_likelihoods: np.ndarray
    process_log_likelihoods: np.ndarray
    candidate_log_likelihoods: np.ndarray
    prior_probabilities: np.ndarray
    posterior_probabilities: np.ndarray
    parameter_prior_marginals: np.ndarray
    parameter_posterior_marginals: np.ndarray
    process_prior_marginals: np.ndarray
    process_posterior_marginals: np.ndarray
    switch_mask: np.ndarray


def _sample_index(probabilities: np.ndarray, uniform_value: float) -> int:
    cumulative = np.cumsum(probabilities)
    return min(int(np.searchsorted(cumulative, uniform_value, side="right")), len(probabilities) - 1)


def run_model_probability_validation(
    trial_seeds: Sequence[int],
    days: int,
    parameter_ids: Sequence[str],
    process_ids: Sequence[str],
    candidate_factors: Sequence[tuple[str, str]],
    transition_matrix,
    factor_emission_means: Sequence[float],
    emission_standard_deviation: float,
) -> ModelProbabilityValidationResult:
    """Generate a nine-mode Markov truth and apply production probability helpers only."""
    parameters = tuple(str(value) for value in parameter_ids)
    processes = tuple(str(value) for value in process_ids)
    if len(parameters) != 3 or len(set(parameters)) != 3:
        raise ValueError("parameter_ids must contain exactly three unique values")
    if len(processes) != 3 or len(set(processes)) != 3:
        raise ValueError("process_ids must contain exactly three unique values")
    factors = tuple((str(parameter), str(process)) for parameter, process in candidate_factors)
    expected_factors = tuple(
        (parameter, process) for parameter in parameters for process in processes
    )
    if factors != expected_factors:
        raise ValueError("candidate_factors must be the complete parameter-major three by three grid")
    seeds_raw = tuple(trial_seeds)
    if not seeds_raw or any(isinstance(value, bool) for value in seeds_raw):
        raise ValueError("trial_seeds must contain unique integers")
    seeds = np.asarray(seeds_raw, dtype=np.int64)
    if any(int(seeds[index]) != seeds_raw[index] for index in range(len(seeds))):
        raise ValueError("trial_seeds must contain unique integers")
    if len(set(seeds.tolist())) != len(seeds):
        raise ValueError("trial_seeds must contain unique integers")
    day_count = int(days)
    if isinstance(days, bool) or day_count != days or day_count <= 0:
        raise ValueError("days must be a positive integer")
    means = np.asarray(tuple(factor_emission_means), dtype=np.float64)
    if means.shape != (3,) or not np.all(np.isfinite(means)) or len(set(means.tolist())) != 3:
        raise ValueError("factor_emission_means must contain three distinct finite values")
    emission_std = float(emission_standard_deviation)
    if not np.isfinite(emission_std) or emission_std <= 0.0:
        raise ValueError("emission_standard_deviation must be finite and positive")
    transition = np.asarray(transition_matrix, dtype=np.float64)
    if transition.shape != (9, 9):
        raise ValueError("transition_matrix must have shape (9, 9)")
    if not np.all(np.isfinite(transition)) or np.any(transition < 0.0):
        raise ValueError("transition_matrix must be finite and nonnegative")
    if not np.allclose(transition.sum(axis=1), 1.0, rtol=0.0, atol=1e-12):
        raise ValueError("transition_matrix rows must sum to one")
    transition = transition / transition.sum(axis=1, keepdims=True)

    trial_count = len(seeds)
    candidate_parameter_indices = np.repeat(np.arange(3), 3)
    candidate_process_indices = np.tile(np.arange(3), 3)
    transition_uniforms = np.empty((trial_count, day_count), dtype=np.float64)
    emission_standard_normals = np.empty((trial_count, day_count, 2), dtype=np.float64)
    true_candidate_indices = np.empty((trial_count, day_count), dtype=np.int64)
    observations = np.empty((trial_count, day_count, 2), dtype=np.float64)
    parameter_log_likelihoods = np.empty((trial_count, day_count, 3), dtype=np.float64)
    process_log_likelihoods = np.empty_like(parameter_log_likelihoods)
    candidate_log_likelihoods = np.empty((trial_count, day_count, 9), dtype=np.float64)
    prior_probabilities = np.empty_like(candidate_log_likelihoods)
    posterior_probabilities = np.empty_like(candidate_log_likelihoods)
    parameter_prior_marginals = np.empty((trial_count, day_count, 3), dtype=np.float64)
    parameter_posterior_marginals = np.empty_like(parameter_prior_marginals)
    process_prior_marginals = np.empty_like(parameter_prior_marginals)
    process_posterior_marginals = np.empty_like(parameter_prior_marginals)
    switch_mask = np.zeros((trial_count, day_count), dtype=bool)
    initial = np.full(9, 1.0 / 9.0, dtype=np.float64)
    gaussian_constant = np.log(2.0 * np.pi * emission_std**2)

    for trial, seed in enumerate(seeds):
        mode_sequence, emission_sequence = np.random.SeedSequence(int(seed)).spawn(2)
        mode_rng = np.random.default_rng(mode_sequence)
        emission_rng = np.random.default_rng(emission_sequence)
        uniforms = mode_rng.random(day_count)
        standard_normals = emission_rng.standard_normal((day_count, 2))
        transition_uniforms[trial] = uniforms
        emission_standard_normals[trial] = standard_normals
        previous_posterior = initial.copy()
        previous_true = None
        for day in range(day_count):
            if day == 0:
                prior = initial.copy()
                true_index = _sample_index(initial, uniforms[day])
            else:
                prior = predict_model_probabilities(transition, previous_posterior)
                true_index = _sample_index(transition[previous_true], uniforms[day])
                switch_mask[trial, day] = true_index != previous_true
            true_parameter = candidate_parameter_indices[true_index]
            true_process = candidate_process_indices[true_index]
            observation = np.asarray(
                [means[true_parameter], means[true_process]], dtype=np.float64
            ) + emission_std * standard_normals[day]
            parameter_log = -0.5 * (
                gaussian_constant + np.square((observation[0] - means) / emission_std)
            )
            process_log = -0.5 * (
                gaussian_constant + np.square((observation[1] - means) / emission_std)
            )
            joint_log = (
                parameter_log[candidate_parameter_indices]
                + process_log[candidate_process_indices]
            )
            posterior = update_model_probabilities(prior, joint_log)
            true_candidate_indices[trial, day] = true_index
            observations[trial, day] = observation
            parameter_log_likelihoods[trial, day] = parameter_log
            process_log_likelihoods[trial, day] = process_log
            candidate_log_likelihoods[trial, day] = joint_log
            prior_probabilities[trial, day] = prior
            posterior_probabilities[trial, day] = posterior
            prior_grid = prior.reshape(3, 3)
            posterior_grid = posterior.reshape(3, 3)
            parameter_prior_marginals[trial, day] = prior_grid.sum(axis=1)
            parameter_posterior_marginals[trial, day] = posterior_grid.sum(axis=1)
            process_prior_marginals[trial, day] = prior_grid.sum(axis=0)
            process_posterior_marginals[trial, day] = posterior_grid.sum(axis=0)
            previous_posterior = posterior
            previous_true = true_index

    return ModelProbabilityValidationResult(
        trial_seeds=seeds.copy(),
        parameter_ids=parameters,
        process_ids=processes,
        candidate_factors=factors,
        candidate_parameter_indices=candidate_parameter_indices,
        candidate_process_indices=candidate_process_indices,
        transition_matrix=transition,
        transition_uniforms=transition_uniforms,
        emission_standard_normals=emission_standard_normals,
        true_candidate_indices=true_candidate_indices,
        observations=observations,
        parameter_log_likelihoods=parameter_log_likelihoods,
        process_log_likelihoods=process_log_likelihoods,
        candidate_log_likelihoods=candidate_log_likelihoods,
        prior_probabilities=prior_probabilities,
        posterior_probabilities=posterior_probabilities,
        parameter_prior_marginals=parameter_prior_marginals,
        parameter_posterior_marginals=parameter_posterior_marginals,
        process_prior_marginals=process_prior_marginals,
        process_posterior_marginals=process_posterior_marginals,
        switch_mask=switch_mask,
    )
