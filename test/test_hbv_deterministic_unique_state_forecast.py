import inspect

import numpy as np

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES
from hbv_multilead_joint_uncertainty.deterministic_unique_state_forecast import (
    PARAMETER_SOURCES,
    STATE_SOURCES,
    build_all_stage_daily_index,
    build_factorial_state_sources,
    forecast_deterministic_state,
    summarize_complete_state_error,
)
from hbv_multilead_joint_uncertainty.synthetic_truth import (
    advance_reference_state,
    reference_routed_discharge,
)


def _parameters():
    values = {
        "parTT": 0.0,
        "parCFMAX": 3.0,
        "parCFR": 0.05,
        "parCWH": 0.1,
        "parFC": 100.0,
        "parBETA": 2.0,
        "parLP": 0.7,
        "parK0": 0.3,
        "parK1": 0.1,
        "parUZL": 5.0,
        "parPERC": 1.0,
        "parK2": 0.02,
        "lag_time": 3.0,
    }
    return np.asarray([values[name] for name in PARAMETER_NAMES])


def test_deterministic_forecast_interface_has_no_covariance_or_observations():
    signature = inspect.signature(forecast_deterministic_state)
    assert tuple(signature.parameters) == (
        "state",
        "parameters",
        "future_forcing",
        "lead_days",
    )


def test_all_daily_origins_map_t_plus_h_without_dropping_final_origins():
    schedule = np.concatenate(
        (np.zeros(180, dtype=int), np.ones(180, dtype=int), np.full(187, 2, dtype=int))
    )[None, :]
    index = build_all_stage_daily_index(schedule)
    assert np.array_equal(index.origin_indices, np.arange(540))
    assert np.array_equal(
        index.target_indices,
        index.origin_indices[:, None] + np.arange(1, 8),
    )
    assert index.target_indices[-1, -1] == 546
    assert not index.same_stage_mask[0, 179, 0]
    assert index.same_stage_mask[0, 180, 6]
    assert index.same_stage_mask[0, 539, 6]


def test_attribution_factorial_is_four_by_three():
    assert STATE_SOURCES == (
        "posterior_all_states",
        "truth_all_states",
        "posterior_hydrologic_truth_routing",
        "truth_hydrologic_posterior_routing",
    )
    assert PARAMETER_SOURCES == (
        "true_stage_parameters",
        "posterior_weighted_parameters",
        "maximum_posterior_parameters",
    )


def test_deterministic_forecast_matches_independent_reference_and_copies_state():
    parameters = _parameters()
    state = np.asarray([2.0, 0.1, 40.0, 3.0, 20.0] + list(np.arange(10, dtype=float)))
    original = state.copy()
    forcing = np.asarray([[2.0, 0.5, 1.0], [0.0, 0.4, -1.0], [5.0, 0.3, 2.0]])
    result = forecast_deterministic_state(state, parameters, forcing, (1, 2, 3))
    expected_states = []
    expected_discharge = []
    current = state.copy()
    mapping = {name: float(value) for name, value in zip(PARAMETER_NAMES, parameters)}
    for daily_forcing in forcing:
        current = advance_reference_state(current, *daily_forcing, mapping)
        expected_states.append(current.copy())
        expected_discharge.append(reference_routed_discharge(current, mapping["lag_time"]))
    assert np.array_equal(state, original)
    assert np.allclose(result.states, expected_states, rtol=0.0, atol=1e-12)
    assert np.allclose(result.discharge, expected_discharge, rtol=0.0, atol=1e-12)


def test_state_sources_replace_only_the_declared_slice():
    posterior = np.arange(2 * 1 * 3 * 15, dtype=float).reshape(2, 1, 3, 15)
    truth = posterior + 1000.0
    sources = build_factorial_state_sources(posterior, truth)
    assert np.array_equal(sources["posterior_all_states"], posterior)
    assert np.array_equal(sources["truth_all_states"], truth)
    assert np.array_equal(
        sources["posterior_hydrologic_truth_routing"][..., :5], posterior[..., :5]
    )
    assert np.array_equal(
        sources["posterior_hydrologic_truth_routing"][..., 5:], truth[..., 5:]
    )
    assert np.array_equal(
        sources["truth_hydrologic_posterior_routing"][..., :5], truth[..., :5]
    )
    assert np.array_equal(
        sources["truth_hydrologic_posterior_routing"][..., 5:], posterior[..., 5:]
    )


def test_complete_state_summary_keeps_all_fifteen_components():
    truth = np.zeros((2, 1, 4, 15), dtype=float)
    estimates = np.zeros((2, 1, 2, 4, 15), dtype=float)
    estimates[:, :, 0, :, :5] = 1.0
    estimates[:, :, 0, :, 5:] = 2.0
    summary = summarize_complete_state_error(estimates, truth, ("first", "second"))
    assert summary["all_day_rmse"].shape == (2, 15)
    assert np.array_equal(summary["all_day_rmse"][0, :5], np.ones(5))
    assert np.array_equal(summary["all_day_rmse"][0, 5:], np.full(10, 2.0))
    assert np.allclose(summary["group_rmse"][0], [1.0, 2.0])
