import sys
from pathlib import Path

import numpy as np
import pytest


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from hbv_joint_uncertainty.imm import (  # noqa: E402
    InteractingMultipleModel,
    normalize_log_weights,
)
from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter  # noqa: E402


def _linear_filter(first_state: float, observation_offset: float = 0.0):
    return ModifiedUnscentedFilter(
        state=np.array([first_state, 2.0, 3.0]),
        covariance=np.eye(3),
        transition=lambda x: x.copy(),
        observation=lambda x: np.array([x[0] + observation_offset]),
        process_covariance=np.zeros((3, 3)),
        observation_covariance=np.eye(1),
        alpha=0.6874,
        beta=2.0,
        kappa=-2.0,
    )


def test_state_interaction_is_confined_to_complete_parameter_group():
    filters = [_linear_filter(value) for value in (0.0, 2.0, 100.0, 102.0)]
    estimator = InteractingMultipleModel(
        filters=filters,
        transition_matrix=np.full((4, 4), 0.25),
        initial_probabilities=np.full(4, 0.25),
        parameter_groups=("parameter-a", "parameter-a", "parameter-b", "parameter-b"),
    )

    result = estimator.step(50.0)

    assert [candidate.prior_state[0] for candidate in result.candidate_results] == pytest.approx(
        [1.0, 1.0, 101.0, 101.0]
    )
    assert [candidate.prior_covariance[0, 0] for candidate in result.candidate_results] == pytest.approx(
        [2.0, 2.0, 2.0, 2.0]
    )


def test_probability_prediction_uses_complete_transition_matrix_across_groups():
    transition = np.array(
        [
            [0.8, 0.1, 0.1],
            [0.2, 0.7, 0.1],
            [0.1, 0.2, 0.7],
        ]
    )
    initial = np.array([0.6, 0.3, 0.1])
    estimator = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(1.0), _linear_filter(2.0)],
        transition_matrix=transition,
        initial_probabilities=initial,
        parameter_groups=("a", "a", "b"),
    )

    result = estimator.step(1.0)
    np.testing.assert_allclose(result.prior_probabilities, transition.T @ initial, rtol=0.0, atol=1e-15)


def test_log_weight_normalization_remains_finite_for_extreme_values():
    probabilities = normalize_log_weights(np.array([-10000.0, -10001.0, -12000.0]))
    assert np.all(np.isfinite(probabilities))
    assert np.all(probabilities >= 0.0)
    assert probabilities.sum() == pytest.approx(1.0, abs=1e-15)
    assert probabilities[0] / probabilities[1] == pytest.approx(np.e, rel=1e-12)


def test_one_candidate_reduces_exactly_to_standalone_filter():
    standalone = _linear_filter(1.0)
    candidate = _linear_filter(1.0)
    standalone_result = standalone.step(2.0)
    estimator = InteractingMultipleModel(
        filters=[candidate],
        transition_matrix=np.ones((1, 1)),
        initial_probabilities=np.ones(1),
        parameter_groups=("only-parameter",),
    )

    result = estimator.step(2.0)
    candidate_result = result.candidate_results[0]

    np.testing.assert_array_equal(candidate_result.prior_state, standalone_result.prior_state)
    np.testing.assert_array_equal(candidate_result.prior_covariance, standalone_result.prior_covariance)
    np.testing.assert_array_equal(candidate_result.posterior_state, standalone_result.posterior_state)
    np.testing.assert_array_equal(candidate_result.posterior_covariance, standalone_result.posterior_covariance)
    assert candidate_result.log_likelihood == standalone_result.log_likelihood
    np.testing.assert_array_equal(result.combined_state, standalone_result.posterior_state)
    np.testing.assert_array_equal(result.combined_covariance, standalone_result.posterior_covariance)
    np.testing.assert_array_equal(
        result.global_posterior_state, standalone_result.posterior_state
    )
    np.testing.assert_array_equal(
        result.global_posterior_covariance,
        standalone_result.posterior_covariance,
    )
    np.testing.assert_array_equal(
        estimator.global_posterior_state, standalone_result.posterior_state
    )
    np.testing.assert_array_equal(result.posterior_probabilities, np.ones(1))


@pytest.mark.parametrize("interaction_mode", ("full", "none"))
def test_each_mode_publishes_one_probability_weighted_global_posterior(
    interaction_mode,
):
    estimator = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(10.0)],
        transition_matrix=np.array([[0.9, 0.1], [0.2, 0.8]]),
        initial_probabilities=np.array([0.8, 0.2]),
        parameter_groups=("low", "high"),
        interaction_mode=interaction_mode,
    )

    result = estimator.step(4.0)
    expected = sum(
        probability * candidate.posterior_state
        for probability, candidate in zip(
            result.posterior_probabilities, result.candidate_results
        )
    )

    np.testing.assert_allclose(
        result.global_posterior_state, expected, rtol=0.0, atol=1e-14
    )
    np.testing.assert_allclose(
        estimator.global_posterior_state, expected, rtol=0.0, atol=1e-14
    )
    assert len(result.candidate_results) == 2


def test_probabilities_are_finite_nonnegative_and_normalized():
    estimator = InteractingMultipleModel(
        filters=[_linear_filter(0.0, 0.0), _linear_filter(0.0, 100.0), _linear_filter(0.0, -100.0)],
        transition_matrix=np.full((3, 3), 1.0 / 3.0),
        initial_probabilities=np.full(3, 1.0 / 3.0),
        parameter_groups=("a", "b", "c"),
    )
    result = estimator.step(0.0)
    assert np.all(np.isfinite(result.posterior_probabilities))
    assert np.all(result.posterior_probabilities >= 0.0)
    assert abs(result.posterior_probabilities.sum() - 1.0) <= 1e-12


def test_transition_rows_must_be_probability_distributions():
    with pytest.raises(ValueError, match="rows must sum to one"):
        InteractingMultipleModel(
            filters=[_linear_filter(0.0), _linear_filter(1.0)],
            transition_matrix=np.array([[0.9, 0.0], [0.2, 0.8]]),
            initial_probabilities=np.array([0.5, 0.5]),
            parameter_groups=("a", "b"),
        )


def test_cross_parameter_only_transition_keeps_destination_state_without_cross_mixing():
    estimator = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(10.0)],
        transition_matrix=np.array([[0.0, 1.0], [1.0, 0.0]]),
        initial_probabilities=np.array([0.5, 0.5]),
        parameter_groups=("a", "b"),
    )
    result = estimator.step(5.0)
    np.testing.assert_allclose(result.prior_probabilities, [0.5, 0.5], rtol=0.0, atol=0.0)
    assert result.candidate_results[0].prior_state[0] == pytest.approx(0.0)
    assert result.candidate_results[1].prior_state[0] == pytest.approx(10.0)


def test_complete_parameter_tuples_are_valid_group_labels():
    estimator = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(2.0)],
        transition_matrix=np.full((2, 2), 0.5),
        initial_probabilities=np.array([0.5, 0.5]),
        parameter_groups=((1.0, 2.0), (1.0, 2.0)),
    )
    result = estimator.step(1.0)
    assert [candidate.prior_state[0] for candidate in result.candidate_results] == pytest.approx([1.0, 1.0])


def test_zero_probability_candidate_is_allowed_and_remains_zero_when_unreachable():
    estimator = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(10.0)],
        transition_matrix=np.eye(2),
        initial_probabilities=np.array([1.0, 0.0]),
        parameter_groups=("a", "b"),
    )
    result = estimator.step(0.0)
    np.testing.assert_array_equal(result.prior_probabilities, np.array([1.0, 0.0]))
    np.testing.assert_array_equal(result.posterior_probabilities, np.array([1.0, 0.0]))


def test_accepted_probability_tolerance_is_renormalized_before_prediction():
    estimator = InteractingMultipleModel(
        filters=[_linear_filter(0.0)],
        transition_matrix=np.array([[1.0 + 9e-13]]),
        initial_probabilities=np.array([1.0 + 9e-13]),
        parameter_groups=("a",),
    )
    result = estimator.step(0.0)
    assert abs(result.prior_probabilities.sum() - 1.0) <= 1e-15
    assert abs(result.posterior_probabilities.sum() - 1.0) <= 1e-15


def test_estimator_full_interaction_preserves_combined_identity_moments():
    estimator = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(10.0)],
        transition_matrix=np.array([[0.9, 0.1], [0.2, 0.8]], dtype=np.float64),
        initial_probabilities=np.array([0.8, 0.2], dtype=np.float64),
        parameter_groups=("low", "high"),
    )
    estimator.interaction_mode = "full"
    original_states = np.asarray([candidate.state for candidate in estimator.filters])
    original_covariances = np.asarray(
        [candidate.covariance for candidate in estimator.filters]
    )
    original_mean = estimator.probabilities @ original_states
    original_covariance = np.zeros((3, 3), dtype=np.float64)
    for probability, state, covariance in zip(
        estimator.probabilities, original_states, original_covariances
    ):
        difference = state - original_mean
        original_covariance += probability * (
            covariance + np.outer(difference, difference)
        )

    prior_probabilities = estimator._interact()
    mixed_states = np.asarray([candidate.state for candidate in estimator.filters])
    mixed_covariances = np.asarray(
        [candidate.covariance for candidate in estimator.filters]
    )
    mixed_mean = prior_probabilities @ mixed_states
    mixed_covariance = np.zeros((3, 3), dtype=np.float64)
    for probability, state, covariance in zip(
        prior_probabilities, mixed_states, mixed_covariances
    ):
        difference = state - mixed_mean
        mixed_covariance += probability * (
            covariance + np.outer(difference, difference)
        )

    np.testing.assert_allclose(mixed_mean, original_mean, rtol=0.0, atol=1e-14)
    np.testing.assert_allclose(mixed_covariance, original_covariance, rtol=0.0, atol=1e-13)
