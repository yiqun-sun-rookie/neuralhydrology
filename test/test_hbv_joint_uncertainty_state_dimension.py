import sys
from pathlib import Path

import numpy as np
import pytest


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from hbv_joint_uncertainty.hbv_adapter import (  # noqa: E402
    HYDRO_STATE_NAMES,
    ROUTING_STATE_NAMES,
    STATE_NAMES,
    pack_state,
    routed_discharge,
)


def test_exact_post_transition_state_has_five_stores_and_ten_routing_values():
    assert HYDRO_STATE_NAMES == ("SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ")
    assert ROUTING_STATE_NAMES == tuple(f"qraw_t_minus_{offset}" for offset in range(10))
    assert len(STATE_NAMES) == 15


def test_ten_day_observation_depends_on_oldest_routing_value():
    hydrologic = np.array([2.0, 0.1, 80.0, 4.0, 12.0])
    newest_nine = np.zeros(9)
    state_without_old_pulse = pack_state(hydrologic, np.r_[newest_nine, 0.0])
    state_with_old_pulse = pack_state(hydrologic, np.r_[newest_nine, 55.0])

    assert np.array_equal(state_without_old_pulse[:14], state_with_old_pulse[:14])
    assert routed_discharge(state_without_old_pulse, lag_time=10.0) == 0.0
    assert routed_discharge(state_with_old_pulse, lag_time=10.0) == pytest.approx(1.0)


def test_routing_weights_match_authoritative_recession_half_triangle():
    hydrologic = np.zeros(5)
    for offset, expected in enumerate(np.arange(10, 0, -1, dtype=float) / 55.0):
        routing = np.zeros(10)
        routing[offset] = 1.0
        state = pack_state(hydrologic, routing)
        assert routed_discharge(state, lag_time=10.0) == pytest.approx(expected)


@pytest.mark.parametrize("lag_time", [0.99, 10.01, np.nan, np.inf])
def test_routing_rejects_lag_outside_frozen_v1_contract(lag_time):
    with pytest.raises(ValueError):
        routed_discharge(np.zeros(15), lag_time=lag_time)


def test_pack_state_rejects_wrong_component_counts():
    with pytest.raises(ValueError):
        pack_state(np.zeros(4), np.zeros(10))
    with pytest.raises(ValueError):
        pack_state(np.zeros(5), np.zeros(9))

