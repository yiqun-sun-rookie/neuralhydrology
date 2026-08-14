import math
import sys
from pathlib import Path

import numpy as np
import pytest


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

import hbv_joint_uncertainty.imm as imm_module  # noqa: E402
from hbv_joint_uncertainty.imm import (  # noqa: E402
    InteractingMultipleModel,
    PairwisePathMultipleModel,
    PairwisePathStepResult,
    interact_model_states,
    normalize_log_weights,
    normalize_log_weights_with_logs,
)
from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter  # noqa: E402


def _direct_and_destination_mixture_moments(states, variances, weights):
    state_values = np.asarray(states, dtype=np.float64)
    variance_values = np.asarray(variances, dtype=np.float64)
    probability_values = np.asarray(weights, dtype=np.float64)
    direct = imm_module._mixture_moments(
        state_values.reshape(-1, 1),
        variance_values.reshape(-1, 1, 1),
        probability_values.reshape(-1),
    )
    destination_states = []
    destination_covariances = []
    for destination in range(probability_values.shape[1]):
        state, covariance = imm_module._mixture_moments(
            state_values[:, destination, None],
            variance_values[:, destination, None, None],
            probability_values[:, destination],
        )
        destination_states.append(state)
        destination_covariances.append(covariance)
    nested = imm_module._mixture_moments(
        np.asarray(destination_states),
        np.asarray(destination_covariances),
        probability_values.sum(axis=0),
    )
    return direct, nested


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


def test_student_t_log_model_evidence_matches_scalar_cauchy_closed_form():
    innovation = np.array([3.0], dtype=np.float64)
    innovation_scale = np.array([[4.0]], dtype=np.float64)

    actual = imm_module.student_t_log_model_evidence(
        innovation,
        innovation_scale,
        degrees_of_freedom=1.0,
    )

    expected = -math.log(math.pi) - 0.5 * math.log(4.0) - math.log1p(9.0 / 4.0)
    assert actual == pytest.approx(expected, rel=0.0, abs=1e-15)


def test_student_t_log_model_evidence_matches_multivariate_closed_form():
    innovation = np.array([1.0, -2.0], dtype=np.float64)
    innovation_scale = np.diag([2.0, 3.0]).astype(np.float64)
    degrees_of_freedom = 5.0
    dimension = 2
    squared_distance = float(
        innovation @ np.linalg.solve(innovation_scale, innovation)
    )
    expected = (
        math.lgamma((degrees_of_freedom + dimension) / 2.0)
        - math.lgamma(degrees_of_freedom / 2.0)
        - 0.5
        * (
            np.linalg.slogdet(innovation_scale)[1]
            + dimension * math.log(degrees_of_freedom * math.pi)
        )
        - 0.5
        * (degrees_of_freedom + dimension)
        * math.log1p(squared_distance / degrees_of_freedom)
    )

    actual = imm_module.student_t_log_model_evidence(
        innovation,
        innovation_scale,
        degrees_of_freedom,
    )

    assert actual == pytest.approx(expected, rel=0.0, abs=1e-15)


@pytest.mark.parametrize("degrees_of_freedom", [0.0, -1.0, np.inf, np.nan])
def test_student_t_log_model_evidence_rejects_invalid_degrees_of_freedom(
    degrees_of_freedom,
):
    with pytest.raises(ValueError, match="degrees of freedom"):
        imm_module.student_t_log_model_evidence(
            np.array([0.0]),
            np.eye(1),
            degrees_of_freedom,
        )


@pytest.mark.parametrize(
    "innovation,innovation_scale,message",
    [
        (np.array([[0.0]]), np.eye(1), "one-dimensional"),
        (np.array([0.0, 1.0]), np.eye(1), "shape"),
        (np.array([np.nan]), np.eye(1), "finite"),
        (np.array([0.0]), np.array([[np.nan]]), "finite"),
        (np.array([0.0, 1.0]), np.array([[1.0, 0.5], [0.0, 1.0]]), "symmetric"),
        (np.array([0.0]), np.array([[0.0]]), "positive definite"),
    ],
)
def test_student_t_log_model_evidence_rejects_invalid_innovation_scale(
    innovation,
    innovation_scale,
    message,
):
    with pytest.raises(ValueError, match=message):
        imm_module.student_t_log_model_evidence(
            innovation,
            innovation_scale,
            degrees_of_freedom=1.0,
        )


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
    np.testing.assert_array_equal(result.posterior_probabilities, np.ones(1))


def test_interacting_model_uses_injected_model_evidence_only_for_weights():
    default = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(4.0)],
        transition_matrix=np.eye(2),
        initial_probabilities=np.full(2, 0.5),
        parameter_groups=("low", "high"),
    )
    scores = iter([0.0, -2.0])
    calls = []

    def fixed_evidence(result):
        calls.append(result)
        return next(scores)

    custom = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(4.0)],
        transition_matrix=np.eye(2),
        initial_probabilities=np.full(2, 0.5),
        parameter_groups=("low", "high"),
        model_evidence_scorer=fixed_evidence,
    )

    default_result = default.step(np.array([1.0]))
    custom_result = custom.step(np.array([1.0]))
    expected_probabilities = normalize_log_weights(
        np.log(np.full(2, 0.5)) + np.array([0.0, -2.0])
    )

    assert len(calls) == 2
    assert calls == list(custom_result.candidate_results)
    np.testing.assert_array_equal(
        custom_result.candidate_log_evidences,
        np.array([0.0, -2.0]),
    )
    np.testing.assert_allclose(
        custom_result.posterior_probabilities,
        expected_probabilities,
        rtol=0.0,
        atol=1e-15,
    )
    for default_candidate, custom_candidate in zip(
        default_result.candidate_results,
        custom_result.candidate_results,
    ):
        np.testing.assert_array_equal(
            custom_candidate.posterior_state,
            default_candidate.posterior_state,
        )
        np.testing.assert_array_equal(
            custom_candidate.posterior_covariance,
            default_candidate.posterior_covariance,
        )


def test_interacting_explicit_gaussian_evidence_is_bitwise_default():
    default = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(4.0)],
        transition_matrix=np.array([[0.9, 0.1], [0.2, 0.8]]),
        initial_probabilities=np.array([0.7, 0.3]),
        parameter_groups=("low", "high"),
    )
    explicit = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(4.0)],
        transition_matrix=np.array([[0.9, 0.1], [0.2, 0.8]]),
        initial_probabilities=np.array([0.7, 0.3]),
        parameter_groups=("low", "high"),
        model_evidence_scorer=lambda result: result.log_likelihood,
    )

    default_result = default.step(np.array([1.0]))
    explicit_result = explicit.step(np.array([1.0]))

    for name in (
        "prior_probabilities",
        "posterior_probabilities",
        "posterior_log_probabilities",
        "candidate_log_evidences",
        "combined_state",
        "combined_covariance",
    ):
        np.testing.assert_array_equal(
            getattr(explicit_result, name),
            getattr(default_result, name),
        )


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


def test_full_interaction_maps_each_source_before_destination_conditioned_mixing():
    states = np.array([[80.0, 10.0], [160.0, 20.0]], dtype=np.float64)
    covariances = np.zeros((2, 2, 2), dtype=np.float64)
    transition = np.array([[0.8, 0.2], [0.3, 0.7]], dtype=np.float64)
    probabilities = np.array([0.75, 0.25], dtype=np.float64)
    capacities = (100.0, 200.0)

    def convert(source, destination, mean, covariance):
        converted = mean.copy()
        if capacities[destination] < capacities[source] and converted[0] > capacities[destination]:
            excess = converted[0] - capacities[destination]
            converted[0] = capacities[destination]
            converted[1] += excess
        return converted, covariance.copy()

    result = interact_model_states(
        states=states,
        covariances=covariances,
        transition_matrix=transition,
        current_probabilities=probabilities,
        parameter_groups=("low", "high"),
        interaction_mode="full",
        pairwise_moment_transform=convert,
    )

    np.testing.assert_allclose(
        result.conditional_weights[0],
        np.array([8.0 / 9.0, 1.0 / 9.0]),
        rtol=0.0,
        atol=1e-15,
    )
    np.testing.assert_allclose(
        result.mixed_states[0],
        np.array([82.22222222222223, 17.77777777777778]),
        rtol=0.0,
        atol=1e-13,
    )


def test_identity_pairwise_transform_is_numerically_identical_to_legacy_interaction():
    states = np.array([[1.0, 2.0], [4.0, 8.0]], dtype=np.float64)
    covariances = np.array([np.eye(2), 2.0 * np.eye(2)])
    arguments = dict(
        states=states,
        covariances=covariances,
        transition_matrix=np.array([[0.9, 0.1], [0.2, 0.8]]),
        current_probabilities=np.array([0.7, 0.3]),
        parameter_groups=("a", "b"),
        interaction_mode="full",
    )

    legacy = interact_model_states(**arguments)
    explicit_identity = interact_model_states(
        **arguments,
        pairwise_moment_transform=lambda source, destination, mean, covariance: (
            mean.copy(),
            covariance.copy(),
        ),
    )

    np.testing.assert_array_equal(
        explicit_identity.prior_probabilities,
        legacy.prior_probabilities,
    )
    np.testing.assert_array_equal(
        explicit_identity.conditional_weights,
        legacy.conditional_weights,
    )
    np.testing.assert_array_equal(explicit_identity.mixed_states, legacy.mixed_states)
    np.testing.assert_array_equal(
        explicit_identity.mixed_covariances,
        legacy.mixed_covariances,
    )


def test_no_interaction_does_not_invoke_pairwise_transform():
    def forbidden_transform(*args):
        raise AssertionError("no-interaction mode must not transform moments")

    result = interact_model_states(
        states=np.array([[1.0], [2.0]]),
        covariances=np.zeros((2, 1, 1)),
        transition_matrix=np.full((2, 2), 0.5),
        current_probabilities=np.full(2, 0.5),
        parameter_groups=("a", "b"),
        interaction_mode="none",
        pairwise_moment_transform=forbidden_transform,
    )

    np.testing.assert_array_equal(result.mixed_states, np.array([[1.0], [2.0]]))


def test_estimator_passes_pairwise_transform_to_full_interaction():
    calls = []

    def record_transform(source, destination, mean, covariance):
        calls.append((source, destination))
        return mean.copy(), covariance.copy()

    estimator = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(10.0)],
        transition_matrix=np.full((2, 2), 0.5),
        initial_probabilities=np.full(2, 0.5),
        parameter_groups=("a", "b"),
        pairwise_moment_transform=record_transform,
    )
    estimator.interaction_mode = "full"

    estimator.interact()

    assert calls == [(0, 0), (1, 0), (0, 1), (1, 1)]


def test_log_weight_normalization_preserves_finite_logs_when_probability_underflows():
    probabilities, log_probabilities = normalize_log_weights_with_logs(
        np.array([0.0, -1000.0, -2000.0], dtype=np.float64)
    )

    np.testing.assert_array_equal(probabilities, np.array([1.0, 0.0, 0.0]))
    np.testing.assert_allclose(
        log_probabilities,
        np.array([0.0, -1000.0, -2000.0]),
        rtol=0.0,
        atol=0.0,
    )
    assert np.all(np.isfinite(log_probabilities))


def test_step_equals_explicit_interaction_then_update():
    transition = np.array([[0.9, 0.1], [0.2, 0.8]], dtype=np.float64)
    initial = np.array([0.7, 0.3], dtype=np.float64)
    direct = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(3.0)],
        transition_matrix=transition,
        initial_probabilities=initial,
        parameter_groups=("same", "same"),
    )
    explicit = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(3.0)],
        transition_matrix=transition,
        initial_probabilities=initial,
        parameter_groups=("same", "same"),
    )
    direct.interaction_mode = "full"
    explicit.interaction_mode = "full"

    direct_result = direct.step(np.array([1.5]))
    explicit_prior = explicit.interact()
    explicit_result = explicit.update_after_interaction(
        np.array([1.5]), explicit_prior
    )

    np.testing.assert_array_equal(
        explicit_result.prior_probabilities, direct_result.prior_probabilities
    )
    np.testing.assert_array_equal(
        explicit_result.posterior_probabilities,
        direct_result.posterior_probabilities,
    )
    np.testing.assert_array_equal(
        explicit_result.posterior_log_probabilities,
        direct_result.posterior_log_probabilities,
    )
    np.testing.assert_array_equal(
        explicit_result.combined_state, direct_result.combined_state
    )
    np.testing.assert_array_equal(
        explicit_result.combined_covariance, direct_result.combined_covariance
    )


@pytest.mark.parametrize(
    "prior, message",
    [
        (np.array([1.0]), "shape"),
        (np.array([0.4, 0.4]), "sum to one"),
        (np.array([0.5, np.nan]), "finite"),
    ],
)
def test_update_after_interaction_rejects_invalid_prior_probabilities(prior, message):
    estimator = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(1.0)],
        transition_matrix=np.full((2, 2), 0.5),
        initial_probabilities=np.array([0.5, 0.5]),
        parameter_groups=("same", "same"),
    )

    with pytest.raises(ValueError, match=message):
        estimator.update_after_interaction(np.array([0.0]), prior)


def _pairwise_path_estimator(
    states=(0.0, 4.0),
    transition=None,
    initial=None,
    observation_offsets=(0.0, 0.0),
    transform=None,
    model_evidence_scorer=None,
):
    transition = (
        np.array([[0.9, 0.1], [0.2, 0.8]], dtype=np.float64)
        if transition is None
        else np.asarray(transition, dtype=np.float64)
    )
    initial = (
        np.array([0.7, 0.3], dtype=np.float64)
        if initial is None
        else np.asarray(initial, dtype=np.float64)
    )
    transform = transform or (
        lambda source, destination, mean, covariance: (
            mean.copy(),
            covariance.copy(),
        )
    )
    return PairwisePathMultipleModel(
        filters=[
            _linear_filter(state, offset)
            for state, offset in zip(states, observation_offsets)
        ],
        transition_matrix=transition,
        initial_probabilities=initial,
        pairwise_moment_transform=transform,
        model_evidence_scorer=model_evidence_scorer,
    )


def test_pairwise_path_branch_log_weights_follow_source_destination_formula():
    transition = np.array([[0.9, 0.1], [0.2, 0.8]], dtype=np.float64)
    initial = np.array([0.7, 0.3], dtype=np.float64)
    estimator = _pairwise_path_estimator(
        transition=transition,
        initial=initial,
    )

    result = estimator.step(np.array([1.5]))

    expected_log_prior = np.log(initial)[:, None] + np.log(transition)
    np.testing.assert_allclose(
        result.branch_prior_log_probabilities,
        expected_log_prior,
        rtol=0.0,
        atol=1e-15,
    )
    log_likelihoods = np.array(
        [
            [result.branch_results[source][destination].log_likelihood for destination in range(2)]
            for source in range(2)
        ]
    )
    branch_probabilities, expected_log_posterior = normalize_log_weights_with_logs(
        (expected_log_prior + log_likelihoods).reshape(-1)
    )
    branch_probabilities = branch_probabilities.reshape(2, 2)
    expected_log_posterior = expected_log_posterior.reshape(2, 2)
    np.testing.assert_allclose(
        result.branch_posterior_log_probabilities,
        expected_log_posterior,
        rtol=0.0,
        atol=1e-15,
    )
    np.testing.assert_allclose(
        result.posterior_probabilities,
        branch_probabilities.sum(axis=0),
        rtol=0.0,
        atol=1e-15,
    )
    assert branch_probabilities.sum() == pytest.approx(1.0, abs=1e-15)


def test_pairwise_path_uses_injected_model_evidence_only_for_branch_weights():
    default = _pairwise_path_estimator()
    scores = iter([0.0, -1.0, -2.0, -3.0])
    calls = []

    def fixed_evidence(result):
        calls.append(result)
        return next(scores)

    custom = _pairwise_path_estimator(model_evidence_scorer=fixed_evidence)

    default_result = default.step(np.array([1.5]))
    custom_result = custom.step(np.array([1.5]))
    score_matrix = np.array([[0.0, -1.0], [-2.0, -3.0]])
    expected_branch_probabilities = normalize_log_weights(
        (custom_result.branch_prior_log_probabilities + score_matrix).reshape(-1)
    ).reshape(2, 2)

    assert len(calls) == 4
    assert calls == [
        custom_result.branch_results[source][destination]
        for source in range(2)
        for destination in range(2)
    ]
    np.testing.assert_array_equal(
        custom_result.branch_log_evidences,
        score_matrix,
    )
    np.testing.assert_allclose(
        custom_result.branch_posterior_probabilities,
        expected_branch_probabilities,
        rtol=0.0,
        atol=1e-15,
    )
    for source in range(2):
        for destination in range(2):
            default_branch = default_result.branch_results[source][destination]
            custom_branch = custom_result.branch_results[source][destination]
            np.testing.assert_array_equal(
                custom_branch.posterior_state,
                default_branch.posterior_state,
            )
            np.testing.assert_array_equal(
                custom_branch.posterior_covariance,
                default_branch.posterior_covariance,
            )


def test_pairwise_path_explicit_gaussian_evidence_is_bitwise_default():
    default = _pairwise_path_estimator()
    explicit = _pairwise_path_estimator(
        model_evidence_scorer=lambda result: result.log_likelihood
    )

    default_result = default.step(np.array([1.5]))
    explicit_result = explicit.step(np.array([1.5]))

    for name in (
        "prior_probabilities",
        "posterior_probabilities",
        "posterior_log_probabilities",
        "branch_log_evidences",
        "branch_posterior_log_probabilities",
        "branch_posterior_probabilities",
        "combined_state",
        "combined_covariance",
    ):
        np.testing.assert_array_equal(
            getattr(explicit_result, name),
            getattr(default_result, name),
        )


def test_postcollapse_observation_protects_persistent_destination_path():
    transition = np.array([[0.9, 0.1], [0.1, 0.9]], dtype=np.float64)
    initial = np.array([0.01, 0.99], dtype=np.float64)

    def map_high_source_to_low_destination(source, destination, mean, covariance):
        mapped = mean.copy()
        if source == 1 and destination == 0:
            mapped[0] = 100.0
        return mapped, covariance.copy()

    path_estimator = _pairwise_path_estimator(
        states=(0.0, 10.0),
        transition=transition,
        initial=initial,
        transform=map_high_source_to_low_destination,
    )
    baseline = InteractingMultipleModel(
        filters=[_linear_filter(0.0), _linear_filter(10.0)],
        transition_matrix=transition,
        initial_probabilities=initial,
        parameter_groups=("low", "high"),
        pairwise_moment_transform=map_high_source_to_low_destination,
    )
    baseline.interaction_mode = "full"

    path_result = path_estimator.step(np.array([0.0]))
    baseline_result = baseline.step(np.array([0.0]))

    assert (
        path_result.branch_posterior_log_probabilities[0, 0]
        > path_result.branch_posterior_log_probabilities[1, 0]
    )
    assert path_result.branch_results[0][0].prior_observation[0] == pytest.approx(0.0)
    assert path_result.branch_results[1][0].prior_observation[0] == pytest.approx(100.0)
    assert baseline_result.candidate_results[0].prior_observation[0] > 90.0


def test_pairwise_path_global_moments_equal_direct_branch_mixture():
    estimator = _pairwise_path_estimator()
    result = estimator.step(np.array([1.5]))
    branch_probabilities = normalize_log_weights(
        result.branch_posterior_log_probabilities.reshape(-1)
    ).reshape(2, 2)
    direct_state = np.zeros(3, dtype=np.float64)
    for source in range(2):
        for destination in range(2):
            direct_state += (
                branch_probabilities[source, destination]
                * result.branch_results[source][destination].posterior_state
            )
    direct_covariance = np.zeros((3, 3), dtype=np.float64)
    for source in range(2):
        for destination in range(2):
            branch_result = result.branch_results[source][destination]
            difference = branch_result.posterior_state - direct_state
            direct_covariance += branch_probabilities[source, destination] * (
                branch_result.posterior_covariance + np.outer(difference, difference)
            )

    np.testing.assert_allclose(direct_state, result.combined_state, rtol=0.0, atol=1e-12)
    np.testing.assert_allclose(
        direct_covariance,
        result.combined_covariance,
        rtol=0.0,
        atol=1e-11,
    )


def test_mixture_state_is_stable_across_direct_and_destination_grouping():
    weights = np.array([
        [0.0006652838179881306, 0.8727933568910229, 2.8236505846712783e-06],
        [1.5595891193067865e-06, 0.034169036438093665, 1.0376218701904156e-07],
        [0.08538711304276131, 0.005775988219837104, 0.0012047345884058343],
    ])
    states = np.array([
        [1694.2592666397775, 2376.2862488012147, 1508.512356527004],
        [1839.654952233744, 1990.0215712581935, 2373.961035422844],
        [1790.9201219197164, 916.8727813351793, 2412.503259585945],
    ])

    direct, nested = _direct_and_destination_mixture_moments(
        states,
        np.zeros_like(states),
        weights,
    )

    np.testing.assert_allclose(direct[0], nested[0], rtol=0.0, atol=1e-12)


def test_mixture_covariance_is_stable_across_direct_and_destination_grouping():
    weights = np.array([
        [4.248138204288473e-06, 0.003234004405323051, 0.035499034387065496],
        [0.00024342842718650854, 0.88311714673009, 0.0361897154851882],
        [0.034766249439289035, 0.005943346711396777, 0.001002826276256585],
    ])
    states = np.array([
        [1963.738136377026, 2088.5405898328854, 1903.8273471809666],
        [1953.2563689346146, 2110.6582007177904, 1947.1418377055284],
        [2206.0347755156154, 2177.8428508387174, 2079.2938123646877],
    ])
    variances = np.array([
        [15.496889168047204, 33.8095067974612, 0.0813576500120358],
        [11.17725213723073, 0.014975536040153805, 0.331199098376847],
        [0.13607111386203818, 0.025181954038724953, 0.046806305519811076],
    ])

    direct, nested = _direct_and_destination_mixture_moments(
        states,
        variances,
        weights,
    )

    np.testing.assert_allclose(direct[1], nested[1], rtol=0.0, atol=1e-11)


def test_pairwise_path_single_candidate_reduces_exactly_to_standalone_filter():
    standalone = _linear_filter(1.0)
    expected = standalone.step(np.array([2.0]))
    estimator = PairwisePathMultipleModel(
        filters=[_linear_filter(1.0)],
        transition_matrix=np.ones((1, 1)),
        initial_probabilities=np.ones(1),
        pairwise_moment_transform=lambda source, destination, mean, covariance: (
            mean.copy(),
            covariance.copy(),
        ),
    )

    result = estimator.step(np.array([2.0]))

    assert isinstance(result, PairwisePathStepResult)
    branch = result.branch_results[0][0]
    np.testing.assert_array_equal(branch.prior_state, expected.prior_state)
    np.testing.assert_array_equal(branch.prior_covariance, expected.prior_covariance)
    np.testing.assert_array_equal(branch.posterior_state, expected.posterior_state)
    np.testing.assert_array_equal(branch.posterior_covariance, expected.posterior_covariance)
    np.testing.assert_array_equal(result.combined_state, expected.posterior_state)
    np.testing.assert_array_equal(result.combined_covariance, expected.posterior_covariance)
    np.testing.assert_array_equal(result.posterior_probabilities, np.ones(1))
    np.testing.assert_array_equal(result.posterior_log_probabilities, np.zeros(1))


def test_pairwise_path_second_step_recurses_from_ordinary_posterior_probabilities():
    estimator = _pairwise_path_estimator(
        states=(0.0, 0.0),
        transition=np.eye(2),
        initial=np.full(2, 0.5),
        observation_offsets=(0.0, 100.0),
    )

    first = estimator.step(np.array([0.0]))
    second = estimator.step(np.array([0.0]))

    assert first.posterior_probabilities[1] == 0.0
    assert np.isfinite(first.posterior_log_probabilities[1])
    assert second.branch_prior_log_probabilities[0, 0] == pytest.approx(
        np.log(first.posterior_probabilities[0]),
        abs=0.0,
    )
    assert second.branch_prior_log_probabilities[1, 1] == -np.inf
    assert second.branch_results[1][1] is None
    assert np.all(np.isfinite(second.posterior_probabilities))
    assert second.posterior_probabilities.sum() == pytest.approx(1.0, abs=1e-15)


def test_pairwise_path_transforms_each_active_cross_branch_exactly_once():
    calls = []

    def record_transform(source, destination, mean, covariance):
        calls.append((source, destination))
        return mean.copy(), covariance.copy()

    estimator = _pairwise_path_estimator(transform=record_transform)

    result = estimator.step(np.array([1.0]))

    assert calls == [(0, 1), (1, 0)]
    assert len(estimator.filters) == 2
    assert sum(branch is not None for row in result.branch_results for branch in row) == 4
    assert all(
        np.allclose(covariance, covariance.T, rtol=0.0, atol=1e-12)
        for covariance in result.destination_covariances
    )


def test_pairwise_path_ordinary_zero_destination_is_not_revived_from_stable_logs():
    tiny_state = np.sqrt(4.0 * 746.0)
    transition = np.array(
        [
            [1.0, 0.0, 0.0, 0.0],
            [0.0, 1.0, 0.0, 0.0],
            [0.0, 1.0, 0.0, 0.0],
            [0.0, 1.0, 0.0, 0.0],
        ],
        dtype=np.float64,
    )
    estimator = PairwisePathMultipleModel(
        filters=[
            _linear_filter(value)
            for value in (0.0, tiny_state, tiny_state, tiny_state)
        ],
        transition_matrix=transition,
        initial_probabilities=np.full(4, 0.25),
        pairwise_moment_transform=lambda source, destination, mean, covariance: (
            mean.copy(),
            covariance.copy(),
        ),
    )

    result = estimator.step(np.array([0.0]))
    expected_candidate_probabilities = imm_module._normalize_path_weights(
        result.destination_raw_probabilities
    )

    assert result.destination_raw_probabilities[1] == 0.0
    assert expected_candidate_probabilities[1] == 0.0
    assert np.isfinite(result.posterior_log_probabilities[1])
    np.testing.assert_array_equal(
        result.posterior_probabilities,
        expected_candidate_probabilities,
    )
    assert result.posterior_probabilities[1] == 0.0
    np.testing.assert_array_equal(
        result.destination_conditional_probabilities[:, 1],
        np.zeros(4),
    )
    assert result.destination_reference_indices[1] == -1
    assert np.count_nonzero(result.branch_active_mask[:, 1]) == 3
    np.testing.assert_array_equal(
        estimator.probabilities,
        expected_candidate_probabilities,
    )


def test_pairwise_path_exposes_registered_ordinary_probability_factorization():
    estimator = _pairwise_path_estimator()

    result = estimator.step(np.array([1.5]))

    branch_log_likelihoods = np.array(
        [
            [
                result.branch_results[source][destination].log_likelihood
                for destination in range(2)
            ]
            for source in range(2)
        ],
        dtype=np.float64,
    )
    branch_probabilities, _ = normalize_log_weights_with_logs(
        (
            result.branch_prior_log_probabilities
            + branch_log_likelihoods
        ).reshape(-1)
    )
    branch_probabilities = branch_probabilities.reshape(2, 2)
    destination_raw = np.array(
        [
            math.fsum(float(value) for value in branch_probabilities[:, destination])
            for destination in range(2)
        ],
        dtype=np.float64,
    )
    destination_probabilities = destination_raw / math.fsum(
        float(value) for value in destination_raw
    )
    raw_conditional = np.zeros((2, 2), dtype=np.float64)
    conditional = np.zeros((2, 2), dtype=np.float64)
    for destination in range(2):
        raw_conditional[:, destination] = (
            branch_probabilities[:, destination] / destination_raw[destination]
        )
        conditional[:, destination] = raw_conditional[:, destination] / math.fsum(
            float(value) for value in raw_conditional[:, destination]
        )

    np.testing.assert_array_equal(
        result.branch_posterior_probabilities,
        branch_probabilities,
    )
    np.testing.assert_array_equal(
        result.destination_raw_probabilities,
        destination_raw,
    )
    np.testing.assert_array_equal(
        result.posterior_probabilities,
        destination_probabilities,
    )
    np.testing.assert_array_equal(
        result.destination_raw_conditional_probabilities,
        raw_conditional,
    )
    np.testing.assert_array_equal(
        result.destination_conditional_probabilities,
        conditional,
    )
    np.testing.assert_array_equal(
        result.branch_active_mask,
        np.ones((2, 2), dtype=bool),
    )


def test_path_mixture_divides_by_weight_residual_and_uses_maximum_reference():
    states = np.array([[2.0**39], [0.0]], dtype=np.float64)
    covariances = np.zeros((2, 1, 1), dtype=np.float64)

    state, covariance, reference_index = imm_module._path_mixture_moments(
        states,
        covariances,
        np.array([2.0**-60, 1.0], dtype=np.float64),
    )

    np.testing.assert_array_equal(state, np.array([2.0**-21]))
    np.testing.assert_array_equal(covariance, covariance.T)
    assert reference_index == 1


def test_path_mixture_is_invariant_to_positive_power_of_two_weight_scaling():
    states = np.array([[1.0, -2.0], [4.0, 3.0], [8.0, 1.0]])
    covariances = np.array(
        [np.eye(2), 2.0 * np.eye(2), 3.0 * np.eye(2)],
        dtype=np.float64,
    )
    weights = np.array([0.2, 0.3, 0.5], dtype=np.float64)

    half = imm_module._path_mixture_moments(
        states,
        covariances,
        weights * 0.5,
    )
    double = imm_module._path_mixture_moments(
        states,
        covariances,
        weights * 2.0,
    )

    np.testing.assert_array_equal(half[0], double[0])
    np.testing.assert_array_equal(half[1], double[1])
    assert half[2] == double[2] == 2


def test_path_mixture_reference_tie_uses_smallest_original_index():
    state, covariance, reference_index = imm_module._path_mixture_moments(
        np.array([[10.0], [20.0], [30.0]], dtype=np.float64),
        np.zeros((3, 1, 1), dtype=np.float64),
        np.array([0.5, 0.0, 0.5], dtype=np.float64),
    )

    np.testing.assert_array_equal(state, np.array([20.0]))
    np.testing.assert_array_equal(covariance, np.array([[[100.0]]]).reshape(1, 1))
    assert reference_index == 0


def test_subnormal_path_mass_is_normalized_before_moment_mixing():
    eta = np.nextafter(np.float64(0.0), np.float64(1.0))
    normalized = imm_module._normalize_path_weights(np.array([eta]))

    state, covariance, reference_index = imm_module._path_mixture_moments(
        np.array([[0.5]], dtype=np.float64),
        np.zeros((1, 1, 1), dtype=np.float64),
        normalized,
    )

    np.testing.assert_array_equal(normalized, np.ones(1))
    np.testing.assert_array_equal(state, np.array([0.5]))
    np.testing.assert_array_equal(covariance, np.zeros((1, 1)))
    assert reference_index == 0


def test_pairwise_path_keeps_nested_primary_when_direct_diagnostic_differs(monkeypatch):
    original_mixture = imm_module._path_mixture_moments

    def perturb_direct_diagnostic(states, covariances, probabilities):
        state, covariance, reference_index = original_mixture(
            states,
            covariances,
            probabilities,
        )
        if np.count_nonzero(probabilities) > 2:
            state = state.copy()
            state[0] += 1.0
        return state, covariance, reference_index

    monkeypatch.setattr(
        imm_module,
        "_path_mixture_moments",
        perturb_direct_diagnostic,
    )
    estimator = _pairwise_path_estimator()

    result = estimator.step(np.array([1.5]))

    assert result.direct_state[0] == result.combined_state[0] + 1.0
    np.testing.assert_array_equal(estimator.state, result.combined_state)
    np.testing.assert_array_equal(estimator.covariance, result.combined_covariance)


def test_pairwise_path_reports_registered_reference_indices():
    estimator = _pairwise_path_estimator()

    result = estimator.step(np.array([1.5]))

    expected_destination_references = np.argmax(
        result.destination_conditional_probabilities,
        axis=0,
    )
    np.testing.assert_array_equal(
        result.destination_reference_indices,
        expected_destination_references,
    )
    assert result.global_reference_index == int(
        np.argmax(result.posterior_probabilities)
    )
