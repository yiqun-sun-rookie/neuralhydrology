"""Forecast readout construction and matched-block statistic tests."""

from __future__ import annotations

import copy
import sys
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import (  # noqa: E402
    PARAMETER_NAMES,
    V1_PARAMETER_BOUNDS,
)
from hbv_multilead_joint_uncertainty.methods import (  # noqa: E402
    MethodCandidate,
    build_method_bank,
)
from hbv_multilead_joint_uncertainty.forecast_readout import (  # noqa: E402
    ENSEMBLE_FORECAST_CONTROL,
    HISTORICAL_COVARIANCE_READOUT,
    READOUT_METHODS,
    forecast_readout_variants,
    posterior_moments,
    summarize_readout_forecasts,
    weighted_parameters,
)


def _parameter_vector(field_capacity: float, lag_time: float):
    values = {
        name: 0.5 * (lower + upper)
        for name, (lower, upper) in V1_PARAMETER_BOUNDS.items()
    }
    values["parFC"] = float(field_capacity)
    values["lag_time"] = float(lag_time)
    return values


def _method_candidates():
    covariance = np.eye(15, dtype=np.float64) * 1e-4
    return tuple(
        MethodCandidate(
            candidate_id=f"candidate_{index}",
            parameter_id=f"parameter_{index}",
            process_id="process_2",
            process_scale=1.0,
            parameters=_parameter_vector(field_capacity, lag_time),
            process_covariance=covariance.copy(),
        )
        for index, (field_capacity, lag_time) in enumerate(
            ((200.0, 2.0), (400.0, 4.0), (800.0, 8.0))
        )
    )


def _posterior_bank():
    candidates = _method_candidates()
    state_map = {
        candidate.parameter_id: np.asarray(
            [
                10.0 + index,
                0.5,
                100.0 + 10.0 * index,
                2.0,
                4.0,
                *np.linspace(0.1, 1.0, 10),
            ],
            dtype=np.float64,
        )
        for index, candidate in enumerate(candidates)
    }
    bank = build_method_bank(
        candidates,
        state_map,
        np.eye(15, dtype=np.float64) * 0.01,
        observation_standard_deviation=0.1,
        factor_transition_stay_probability=0.98,
        interaction_mode="full",
    )
    bank.estimator.probabilities = np.asarray([0.2, 0.7, 0.1])
    for index, candidate_filter in enumerate(bank.estimator.filters):
        candidate_filter.state = state_map[f"parameter_{index}"].copy()
        candidate_filter.covariance = (
            np.eye(15, dtype=np.float64) * (index + 1) * 0.02
        )
    states = np.asarray(
        [candidate.state for candidate in bank.estimator.filters]
    )
    covariances = np.asarray(
        [candidate.covariance for candidate in bank.estimator.filters]
    )
    moments = posterior_moments(
        states, covariances, bank.estimator.probabilities
    )
    bank.estimator.state = moments.mean_state.copy()
    bank.estimator.covariance = moments.complete_covariance.copy()
    return bank, candidates


def _synchronize_global_posterior(bank):
    states = np.asarray(
        [candidate.state for candidate in bank.estimator.filters]
    )
    covariances = np.asarray(
        [candidate.covariance for candidate in bank.estimator.filters]
    )
    moments = posterior_moments(
        states, covariances, bank.estimator.probabilities
    )
    bank.estimator.global_posterior_state = moments.mean_state
    bank.estimator.global_posterior_covariance = moments.complete_covariance


def _bank_snapshot(bank):
    return {
        "states": np.asarray(
            [candidate.state for candidate in bank.estimator.filters]
        ).copy(),
        "covariances": np.asarray(
            [candidate.covariance for candidate in bank.estimator.filters]
        ).copy(),
        "probabilities": bank.estimator.probabilities.copy(),
        "combined_state": bank.estimator.state.copy(),
        "combined_covariance": bank.estimator.covariance.copy(),
        "transition_matrix": bank.estimator.transition_matrix.copy(),
    }


def test_posterior_moments_match_explicit_within_and_between_equations():
    states = np.asarray([[1.0, 2.0], [4.0, 6.0], [8.0, 9.0]])
    covariances = np.asarray(
        [
            [[1.0, 0.1], [0.1, 2.0]],
            [[2.0, 0.2], [0.2, 3.0]],
            [[4.0, 0.3], [0.3, 5.0]],
        ]
    )
    weights = np.asarray([0.2, 0.3, 0.5])

    result = posterior_moments(states, covariances, weights)

    expected_mean = weights @ states
    expected_within = np.einsum("i,ijk->jk", weights, covariances)
    expected_between = sum(
        weight * np.outer(state - expected_mean, state - expected_mean)
        for weight, state in zip(weights, states)
    )
    np.testing.assert_allclose(result.mean_state, expected_mean)
    np.testing.assert_allclose(result.within_covariance, expected_within)
    np.testing.assert_allclose(result.between_covariance, expected_between)
    np.testing.assert_allclose(
        result.complete_covariance,
        expected_within + expected_between,
    )


def test_posterior_moments_symmetrize_large_scale_roundoff():
    states = np.asarray(
        [
            [1e8, 1e-8, 3e4],
            [2e8, 2e-8, 4e4],
            [9e8, 7e-8, 5e4],
        ]
    )
    covariances = np.broadcast_to(
        np.eye(3), (3, 3, 3)
    ).copy()

    result = posterior_moments(
        states,
        covariances,
        np.asarray([0.2, 0.3, 0.5]),
    )

    np.testing.assert_array_equal(
        result.between_covariance,
        result.between_covariance.T,
    )
    np.testing.assert_array_equal(
        result.complete_covariance,
        result.complete_covariance.T,
    )


@pytest.mark.parametrize(
    "weights",
    (
        [0.2, 0.8],
        [0.2, -0.1, 0.9],
        [0.2, 0.3, np.nan],
        [0.2, 0.3, 0.4],
    ),
)
def test_posterior_moments_reject_invalid_weights(weights):
    with pytest.raises(ValueError, match="weights"):
        posterior_moments(
            np.zeros((3, 2)),
            np.broadcast_to(np.eye(2), (3, 2, 2)),
            weights,
        )


def test_weighted_parameters_use_frozen_parameter_name_order():
    candidates = _method_candidates()
    weights = np.asarray([0.2, 0.7, 0.1])

    result = weighted_parameters(candidates, weights)

    assert tuple(result) == PARAMETER_NAMES
    for name in PARAMETER_NAMES:
        expected = sum(
            weight * candidate.parameters[name]
            for weight, candidate in zip(weights, candidates)
        )
        assert result[name] == pytest.approx(expected)


def test_readout_variants_are_single_origin_causal_and_do_not_mutate_bank():
    bank, candidates = _posterior_bank()
    before = _bank_snapshot(bank)
    forcing = np.column_stack(
        (
            np.linspace(1.0, 2.0, 7),
            np.linspace(0.2, 0.4, 7),
            np.linspace(-1.0, 3.0, 7),
        )
    )

    result = forecast_readout_variants(
        bank,
        candidates,
        forcing,
        lead_days=tuple(range(1, 8)),
    )

    assert tuple(result.predictions) == READOUT_METHODS
    np.testing.assert_array_equal(
        result.ensemble_control_prediction,
        result.predictions[ENSEMBLE_FORECAST_CONTROL],
    )
    assert HISTORICAL_COVARIANCE_READOUT != ENSEMBLE_FORECAST_CONTROL
    assert not hasattr(result, "primary_prediction")
    assert result.maximum_posterior_index == 1
    for values in result.predictions.values():
        assert values.shape == (7,)
        assert np.all(np.isfinite(values))
    current = result.current_forecast
    np.testing.assert_allclose(
        result.predictions["maximum_posterior_candidate"],
        current.candidate_predictions[:, 1],
        rtol=0.0,
        atol=0.0,
    )
    after = _bank_snapshot(bank)
    for key in before:
        np.testing.assert_array_equal(after[key], before[key])


def test_maximum_posterior_tie_uses_lowest_candidate_index():
    bank, candidates = _posterior_bank()
    bank.estimator.probabilities = np.asarray([0.45, 0.45, 0.10])
    _synchronize_global_posterior(bank)
    forcing = np.zeros((7, 3), dtype=np.float64)

    result = forecast_readout_variants(
        bank,
        candidates,
        forcing,
        lead_days=(1, 7),
    )

    assert result.maximum_posterior_index == 0


def test_unique_readouts_use_the_declared_moments_and_parameters():
    bank, candidates = _posterior_bank()
    result = forecast_readout_variants(
        bank,
        candidates,
        np.zeros((7, 3), dtype=np.float64),
        lead_days=(1, 3, 7),
    )
    states = np.asarray(
        [candidate.state for candidate in bank.estimator.filters]
    )
    covariances = np.asarray(
        [candidate.covariance for candidate in bank.estimator.filters]
    )
    posterior = posterior_moments(
        states, covariances, bank.estimator.probabilities
    )
    uniform = posterior_moments(
        states, covariances, np.full(3, 1.0 / 3.0)
    )

    np.testing.assert_allclose(
        result.global_posterior_state, posterior.mean_state
    )
    np.testing.assert_allclose(
        result.posterior_complete_covariance,
        posterior.complete_covariance,
        rtol=0.0,
        atol=1e-12,
    )
    np.testing.assert_allclose(
        result.posterior_within_covariance,
        posterior.within_covariance,
        rtol=0.0,
        atol=1e-12,
    )
    np.testing.assert_allclose(result.uniform_mean_state, uniform.mean_state)
    np.testing.assert_allclose(
        result.uniform_complete_covariance,
        uniform.complete_covariance,
        rtol=0.0,
        atol=1e-12,
    )
    expected_posterior_parameters = weighted_parameters(
        candidates, bank.estimator.probabilities
    )
    expected_uniform_parameters = weighted_parameters(
        candidates, np.full(3, 1.0 / 3.0)
    )
    np.testing.assert_allclose(
        [result.posterior_weighted_parameters[name] for name in PARAMETER_NAMES],
        [expected_posterior_parameters[name] for name in PARAMETER_NAMES],
        rtol=0.0,
        atol=1e-12,
    )
    np.testing.assert_allclose(
        [result.uniform_parameters[name] for name in PARAMETER_NAMES],
        [expected_uniform_parameters[name] for name in PARAMETER_NAMES],
        rtol=0.0,
        atol=1e-12,
    )
    assert result.maximum_parameters == candidates[1].parameters


def _synthetic_readout_arrays():
    block_count = 4
    truth_count = 2
    origin_count = 5
    lead_count = 7
    truth = np.zeros(
        (block_count, truth_count, origin_count, lead_count),
        dtype=np.float64,
    )
    current = np.ones_like(truth)
    improved = np.full_like(truth, 0.98)
    no_interaction = np.full_like(truth, 1.02)
    one_failed = improved.copy()
    one_failed[..., -1] = 1.0
    mask = np.ones((origin_count, lead_count), dtype=bool)
    mask[-1, 1:] = False
    bootstrap = np.asarray(
        [
            [0, 1, 2, 3],
            [0, 0, 1, 1],
            [2, 2, 3, 3],
            [3, 0, 3, 0],
        ],
        dtype=np.int64,
    )
    return (
        {
            "current_multiple_states": current,
            "posterior_unique_complete_covariance_weighted_parameters": improved,
            "one_failed": one_failed,
            "no_state_interaction_multiple_states": no_interaction,
        },
        truth,
        mask,
        bootstrap,
    )


def test_statistics_use_lead_masks_matched_blocks_and_fixed_boundary():
    forecasts, truth, mask, bootstrap = _synthetic_readout_arrays()
    summary = summarize_readout_forecasts(
        forecasts,
        truth,
        mask,
        days_since_switch=np.arange(mask.shape[0]),
        bootstrap_indices=bootstrap,
        minimum_meaningful_rmse_fraction=0.01,
        replacement_baseline="current_multiple_states",
        general_repair_baseline="no_state_interaction_multiple_states",
    )

    np.testing.assert_allclose(
        summary["rmse"][
            "posterior_unique_complete_covariance_weighted_parameters"
        ],
        np.full(7, 0.98),
    )
    comparison = summary["comparisons"][
        "posterior_unique_complete_covariance_weighted_parameters"
    ]["minus_current_multiple_states"]
    expected_difference = 0.98**2 - 1.0
    np.testing.assert_allclose(
        comparison["block_mean_mse_difference"],
        np.full((4, 7), expected_difference),
    )
    np.testing.assert_allclose(
        comparison["meaningful_improvement_boundary"],
        np.full(7, (1.0 - 0.01) ** 2 - 1.0),
    )
    assert comparison["all_leads_pass"] is True
    assert (
        summary["decisions"][
            "posterior_unique_complete_covariance_weighted_parameters"
        ]["replace_current_multiple_states"]
        is True
    )
    assert (
        summary["decisions"][
            "posterior_unique_complete_covariance_weighted_parameters"
        ]["repair_general_degradation"]
        is True
    )


def test_one_failed_lead_stops_replacement():
    forecasts, truth, mask, bootstrap = _synthetic_readout_arrays()
    summary = summarize_readout_forecasts(
        forecasts,
        truth,
        mask,
        days_since_switch=np.arange(mask.shape[0]),
        bootstrap_indices=bootstrap,
        minimum_meaningful_rmse_fraction=0.01,
        replacement_baseline="current_multiple_states",
        general_repair_baseline="no_state_interaction_multiple_states",
    )

    decision = summary["decisions"]["one_failed"]
    assert decision["replace_current_multiple_states"] is False
    comparison = summary["comparisons"]["one_failed"][
        "minus_current_multiple_states"
    ]
    assert bool(comparison["point_estimate_passes"][-1]) is False


def test_readout_does_not_read_or_change_future_observations():
    bank, candidates = _posterior_bank()
    forcing = np.column_stack((np.ones(7), np.zeros(7), np.zeros(7)))
    bank_copy = copy.deepcopy(bank)

    first = forecast_readout_variants(
        bank,
        candidates,
        forcing,
        lead_days=(1, 3, 7),
    )
    second = forecast_readout_variants(
        bank_copy,
        candidates,
        forcing,
        lead_days=(1, 3, 7),
    )

    for method in READOUT_METHODS:
        np.testing.assert_array_equal(
            first.predictions[method],
            second.predictions[method],
        )
