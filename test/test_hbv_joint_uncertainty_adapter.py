import sys
from pathlib import Path

import numpy as np
import pytest


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from hbv_joint_uncertainty.hbv_adapter import (  # noqa: E402
    advance_state,
    initial_state_vector,
    pack_state,
    routed_discharge,
    simulate_adapter,
)
from scl_hydro.hbv_lite_numpy import (  # noqa: E402
    _half_triangular_lag,
    _simulate_loop,
    simulate_hbv_lite,
)


@pytest.fixture
def params():
    return {
        "parTT": 0.0,
        "parCFMAX": 3.2,
        "parCFR": 0.04,
        "parCWH": 0.1,
        "parFC": 250.0,
        "parBETA": 2.1,
        "parLP": 0.7,
        "parK0": 0.2,
        "parK1": 0.06,
        "parUZL": 18.0,
        "parPERC": 1.2,
        "parK2": 0.015,
        "lag_time": 10.0,
    }


def _forcing(n_days=365):
    rng = np.random.default_rng(314159)
    rain = rng.gamma(0.8, 4.0, size=n_days).astype(np.float64)
    pet = np.maximum(0.0, 2.0 + np.sin(np.linspace(0.0, 2.0 * np.pi, n_days)))
    temp = 4.0 + 12.0 * np.sin(np.linspace(-np.pi / 2.0, 3.0 * np.pi / 2.0, n_days))
    return rain, pet.astype(np.float64), temp.astype(np.float64)


def test_default_state_matches_authoritative_initialization(params):
    state = initial_state_vector(params)
    np.testing.assert_array_equal(state[:5], np.array([0.0, 0.0, 75.0, 5.0, 10.0]))
    np.testing.assert_array_equal(state[5:], np.zeros(10))


def test_one_day_transition_matches_authoritative_loop(params):
    initial = {
        "SNOWPACK": 12.0,
        "MELTWATER": 0.5,
        "SM": 90.0,
        "SUZ": 8.0,
        "SLZ": 30.0,
    }
    state = initial_state_vector(params, initial)
    next_state = advance_state(state, rain=14.0, pet=1.7, temp=2.3, params=params)

    q_raw, snow, meltwater, soil, upper, lower = _simulate_loop(
        np.array([14.0]),
        np.array([1.7]),
        np.array([2.3]),
        initial["SNOWPACK"],
        initial["MELTWATER"],
        initial["SM"],
        initial["SUZ"],
        initial["SLZ"],
        params["parTT"],
        params["parCFMAX"],
        params["parCFR"],
        params["parCWH"],
        params["parFC"],
        params["parBETA"],
        params["parLP"],
        params["parK0"],
        params["parK1"],
        params["parUZL"],
        params["parPERC"],
        params["parK2"],
    )

    np.testing.assert_allclose(next_state[:5], [snow, meltwater, soil, upper, lower], rtol=0.0, atol=1e-12)
    assert next_state[5] == pytest.approx(q_raw[0], abs=1e-12)
    np.testing.assert_array_equal(next_state[6:], np.zeros(9))


def test_sequential_adapter_matches_authoritative_reference_each_day(params):
    rain, pet, temp = _forcing()
    q_adapter, states = simulate_adapter(rain, pet, temp, params)

    reference_stores = []
    reference_qraw = []
    stores = {
        "SNOWPACK": 0.0,
        "MELTWATER": 0.0,
        "SM": params["parFC"] * 0.3,
        "SUZ": 5.0,
        "SLZ": 10.0,
    }
    no_lag = {**params, "lag_time": 1.0}
    for day in range(len(rain)):
        q_day, stores = simulate_hbv_lite(
            rain[day:day + 1],
            pet[day:day + 1],
            temp[day:day + 1],
            no_lag,
            initial_state=stores,
        )
        reference_qraw.append(q_day[0])
        reference_stores.append([stores[name] for name in ("SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ")])

    reference_qraw = np.asarray(reference_qraw)
    reference_stores = np.asarray(reference_stores)
    q_reference = _half_triangular_lag(reference_qraw, params["lag_time"])

    assert np.max(np.abs(states[:, :5] - reference_stores)) <= 1e-8
    assert np.max(np.abs(states[:, 5] - reference_qraw)) <= 1e-8
    assert np.max(np.abs(q_adapter - q_reference)) <= 1e-8


def test_full_series_matches_public_authoritative_function(params):
    rain, pet, temp = _forcing()
    q_adapter, states = simulate_adapter(rain, pet, temp, params)
    q_reference, final_reference = simulate_hbv_lite(rain, pet, temp, params)

    assert np.max(np.abs(q_adapter - q_reference)) <= 1e-8
    np.testing.assert_allclose(
        states[-1, :5],
        [final_reference[name] for name in ("SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ")],
        rtol=0.0,
        atol=1e-8,
    )


def test_series_preserves_last_ten_raw_runoff_values(params):
    rain, pet, temp = _forcing(20)
    _, states = simulate_adapter(rain, pet, temp, params)
    expected = states[:, 5].copy()
    np.testing.assert_allclose(states[-1, 5:], expected[-10:][::-1], rtol=0.0, atol=0.0)


def test_adapter_rejects_parameter_outside_explicit_v1_bounds(params):
    invalid = {**params, "parLP": -4e-8}
    state = initial_state_vector(params)
    with pytest.raises(ValueError, match="parLP"):
        advance_state(state, rain=14.0, pet=1.7, temp=2.3, params=invalid)


@pytest.mark.parametrize("lag_time", [1.01, 9.01])
def test_noninteger_lag_matches_authoritative_ceiling_rule(params, lag_time):
    chronological_raw_runoff = np.arange(1.0, 11.0)
    state = pack_state(np.zeros(5), chronological_raw_runoff[::-1])
    expected = _half_triangular_lag(chronological_raw_runoff, lag_time)[-1]
    assert routed_discharge(state, lag_time) == pytest.approx(expected, abs=1e-12)


def test_transition_shifts_nonzero_routing_history(params):
    routing = np.arange(1.0, 11.0)
    state = pack_state(np.array([2.0, 0.1, 80.0, 4.0, 12.0]), routing)
    next_state = advance_state(state, rain=0.0, pet=0.0, temp=5.0, params=params)
    np.testing.assert_array_equal(next_state[6:], routing[:9])
