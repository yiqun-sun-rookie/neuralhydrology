import sys
from pathlib import Path

import numpy as np
import pytest


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from hbv_joint_uncertainty.sigma_filter import (  # noqa: E402
    ModifiedUnscentedFilter,
    ScaledSigmaPoints,
    unscented_transform,
)


def test_sigma_points_have_expected_count_and_reconstruct_distribution():
    generator = ScaledSigmaPoints(n=15, alpha=0.6874, beta=2.0, kappa=-2.0)
    mean = np.linspace(1.0, 15.0, 15)
    covariance = np.diag(np.linspace(0.1, 1.5, 15))

    sigmas = generator.sigma_points(mean, covariance)
    reconstructed_mean, reconstructed_covariance = unscented_transform(
        sigmas, generator.mean_weights, generator.covariance_weights
    )

    assert sigmas.shape == (31, 15)
    np.testing.assert_allclose(reconstructed_mean, mean, rtol=0.0, atol=1e-12)
    np.testing.assert_allclose(reconstructed_covariance, covariance, rtol=0.0, atol=1e-12)


def test_update_regenerates_measurement_points_after_adding_process_noise():
    state = np.array([1.0, 2.0, 3.0])
    covariance = np.diag([1.0, 2.0, 3.0])
    process_covariance = np.diag([4.0, 0.0, 0.0])
    observation_covariance = np.array([[1.0]])

    estimator = ModifiedUnscentedFilter(
        state=state,
        covariance=covariance,
        transition=lambda x: x.copy(),
        observation=lambda x: np.array([x[0]]),
        process_covariance=process_covariance,
        observation_covariance=observation_covariance,
        alpha=0.6874,
        beta=2.0,
        kappa=-2.0,
    )
    result = estimator.step(np.array([2.0]))

    expected_gain = 5.0 / 6.0
    assert result.prior_observation[0] == pytest.approx(1.0, abs=1e-12)
    assert result.innovation_covariance[0, 0] == pytest.approx(6.0, abs=1e-12)
    assert result.posterior_state[0] == pytest.approx(1.0 + expected_gain, abs=1e-12)
    assert result.posterior_covariance[0, 0] == pytest.approx(5.0 / 6.0, abs=1e-12)


def test_log_likelihood_matches_scalar_gaussian_reference():
    estimator = ModifiedUnscentedFilter(
        state=np.array([1.0, 2.0, 3.0]),
        covariance=np.diag([1.0, 2.0, 3.0]),
        transition=lambda x: x.copy(),
        observation=lambda x: np.array([x[0]]),
        process_covariance=np.diag([4.0, 0.0, 0.0]),
        observation_covariance=np.array([[1.0]]),
        alpha=0.6874,
        beta=2.0,
        kappa=-2.0,
    )
    result = estimator.step(np.array([2.0]))
    expected = -0.5 * (np.log(2.0 * np.pi) + np.log(6.0) + 1.0 / 6.0)
    assert result.log_likelihood == pytest.approx(expected, abs=1e-12)


def test_semidefinite_covariance_uses_bounded_jitter_and_stays_finite():
    generator = ScaledSigmaPoints(n=3, alpha=0.6874, beta=2.0, kappa=-2.0)
    sigmas = generator.sigma_points(np.zeros(3), np.diag([1.0, 0.0, 0.0]))
    assert np.all(np.isfinite(sigmas))


def test_scaled_rank_deficient_covariance_accepts_roundoff_negative_eigenvalue():
    rng = np.random.default_rng(123)
    factors = rng.normal(size=(15, 5)) * 1e4
    covariance = factors @ factors.T
    assert np.min(np.linalg.eigvalsh(covariance)) < -1e-10

    generator = ScaledSigmaPoints(n=15, alpha=0.6874, beta=2.0, kappa=-2.0)
    sigmas = generator.sigma_points(np.zeros(15), covariance)
    assert np.all(np.isfinite(sigmas))


def test_irrecoverably_negative_covariance_is_rejected():
    generator = ScaledSigmaPoints(n=3, alpha=0.6874, beta=2.0, kappa=-2.0)
    with pytest.raises(ValueError, match="positive semidefinite"):
        generator.sigma_points(np.zeros(3), np.diag([1.0, -1.0, 1.0]))


def test_filter_rejects_nonfinite_observation():
    estimator = ModifiedUnscentedFilter(
        state=np.zeros(3),
        covariance=np.eye(3),
        transition=lambda x: x.copy(),
        observation=lambda x: np.array([x[0]]),
        process_covariance=np.zeros((3, 3)),
        observation_covariance=np.eye(1),
        alpha=0.6874,
        beta=2.0,
        kappa=-2.0,
    )
    with pytest.raises(ValueError, match="observation"):
        estimator.step(np.array([np.nan]))


def test_scalar_discharge_observation_matches_length_one_array():
    def make_filter():
        return ModifiedUnscentedFilter(
            state=np.array([1.0, 2.0, 3.0]),
            covariance=np.diag([1.0, 2.0, 3.0]),
            transition=lambda x: x.copy(),
            observation=lambda x: np.array([x[0]]),
            process_covariance=np.diag([4.0, 0.0, 0.0]),
            observation_covariance=np.array([[1.0]]),
            alpha=0.6874,
            beta=2.0,
            kappa=-2.0,
        )

    scalar_result = make_filter().step(2.0)
    array_result = make_filter().step(np.array([2.0]))
    np.testing.assert_allclose(scalar_result.posterior_state, array_result.posterior_state, rtol=0.0, atol=0.0)
    np.testing.assert_allclose(
        scalar_result.posterior_covariance, array_result.posterior_covariance, rtol=0.0, atol=0.0
    )
    assert scalar_result.log_likelihood == array_result.log_likelihood


def test_extreme_finite_observation_produces_finite_log_likelihood():
    estimator = ModifiedUnscentedFilter(
        state=np.zeros(3),
        covariance=np.eye(3),
        transition=lambda x: x.copy(),
        observation=lambda x: np.array([x[0]]),
        process_covariance=np.zeros((3, 3)),
        observation_covariance=np.eye(1),
        alpha=0.6874,
        beta=2.0,
        kappa=-2.0,
    )
    result = estimator.step(2e154)
    assert np.isfinite(result.log_likelihood)


def test_optional_posterior_projector_enforces_physical_state_before_storage():
    estimator = ModifiedUnscentedFilter(
        state=np.array([1.0, 2.0, 3.0]),
        covariance=np.eye(3),
        transition=lambda x: x.copy(),
        observation=lambda x: np.array([x[0]]),
        process_covariance=np.zeros((3, 3)),
        observation_covariance=np.array([[1e-6]]),
        state_projector=lambda x: np.maximum(x, 0.0),
        alpha=0.6874,
        beta=2.0,
        kappa=-2.0,
    )
    result = estimator.step(-10.0)
    assert result.posterior_state[0] == 0.0
    assert estimator.state[0] == 0.0


def test_predict_without_observation_commits_the_same_unscented_prior():
    def make_filter():
        return ModifiedUnscentedFilter(
            state=np.array([1.0, 2.0, 3.0]),
            covariance=np.diag([1.0, 2.0, 3.0]),
            transition=lambda x: np.array([x[0] ** 2, x[1] + 1.0, x[2]]),
            observation=lambda x: np.array([x[0]]),
            process_covariance=np.diag([0.1, 0.0, 0.0]),
            observation_covariance=np.array([[1.0]]),
            alpha=0.6874,
            beta=2.0,
            kappa=-2.0,
        )

    reference = make_filter()
    expected_state, expected_covariance = reference.predict()
    estimator = make_filter()
    state, covariance = estimator.predict_without_observation()

    np.testing.assert_allclose(state, expected_state, rtol=0.0, atol=0.0)
    np.testing.assert_allclose(covariance, expected_covariance, rtol=0.0, atol=0.0)
    np.testing.assert_allclose(estimator.state, expected_state, rtol=0.0, atol=0.0)
    np.testing.assert_allclose(estimator.covariance, expected_covariance, rtol=0.0, atol=0.0)
    estimator.predict_without_observation()
