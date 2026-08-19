"""Contract tests for the stage-3 real-observation module (no filter runs)."""

import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from camels_switch_confirmation.run_online_noise_real_obs import (  # noqa: E402
    ADMISSION_NSE_MIN,
    ARMS,
    BOUNDARY_WEIGHT_MAX,
    LOCKIN_DAYS,
    TRUTH_KEYS,
    _load_cell_npz,
    admission_mask,
    boundary_cell_indices,
    control_members,
    detect_lockin,
    forecast_log_weights,
    mixture_forecast,
    stratum_label,
)
from camels_switch_confirmation.run_online_noise_pilot import (  # noqa: E402
    bma_log_weights,
    grid_cells,
)


def test_admission_rule_applies_all_three_frozen_conditions():
    frame = pd.DataFrame({
        "predicted_identifiable": [True, True, True, False, True],
        "nse_m1": [0.5, ADMISSION_NSE_MIN, 0.29, 0.9, 0.9],
        "fc_clipped_any": [False, False, False, False, True],
    })
    mask = admission_mask(frame)
    assert list(mask) == [True, True, False, False, False]


def test_stratum_labels_use_frozen_edges():
    assert stratum_label(0.5) == "lt1"
    assert stratum_label(1.0) == "1to2"
    assert stratum_label(2.999) == "2to3"
    assert stratum_label(3.0) == "ge3"
    assert stratum_label(float("inf")) == "ge3"


def test_control_bank_is_single_center_member():
    """Amendment 01b: the control is one member, not three identical copies."""
    members = [{"parFC": 100.0, "parBETA": 2.0},
               {"parFC": 50.0, "parBETA": 2.0},
               {"parFC": 200.0, "parBETA": 2.0}]
    control = control_members(members)
    assert len(control) == 1
    assert control[0] == members[0]
    assert control[0] is not members[0]
    members[0]["parFC"] = -1.0  # mutating the source must not leak into the copy
    assert control[0]["parFC"] == 100.0


def test_single_candidate_interact_is_bitwise_identity():
    """Mechanism regression for the retired triplet control: with one member
    the mixing step has a single addend, so states/covariances pass through
    bit-for-bit and no ulp-asymmetry chaos channel exists."""
    from hbv_joint_uncertainty.imm import interact_model_states

    rng = np.random.default_rng(11)
    state = rng.uniform(0.1, 300.0, size=(1, 15))
    factor = rng.normal(size=(15, 15))
    covariance = (factor @ factor.T + 15.0 * np.eye(15))[None]
    result = interact_model_states(
        state, covariance, np.array([[1.0]]), np.array([1.0]),
        parameter_groups=[0], interaction_mode="full",
    )
    assert np.array_equal(result.mixed_states, state)
    assert np.array_equal(result.mixed_covariances, covariance)


def test_ctrl_posterior_gate_accepts_exact_and_rejects_deviation():
    from camels_switch_confirmation.run_online_noise_real_obs import (
        assert_ctrl_posterior_exact,
    )

    exact = np.ones((100, 1))
    assert assert_ctrl_posterior_exact(exact) == 0.0
    drifted = exact.copy()
    drifted[57, 0] = 1.0 - 1e-6
    with pytest.raises(ValueError, match="single-member identity"):
        assert_ctrl_posterior_exact(drifted)
    with pytest.raises(ValueError, match="shape"):
        assert_ctrl_posterior_exact(np.full((100, 3), 1.0 / 3.0))


def test_run_cell_records_failure_instead_of_raising(monkeypatch):
    """Amendment 01b registers the fault-tolerant runner: one poisoned cell
    must yield a failure record, never crash the whole pool."""
    import camels_switch_confirmation.run_online_noise_real_obs as module

    def _boom(basin, arm, m, c):
        raise ValueError("covariance must be positive semidefinite")

    monkeypatch.setattr(module, "_run_cell_inner", _boom)
    record = module._run_cell(("03384450", "P", 10.0, 0.0))
    assert record["status"] == "failed"
    assert record["basin_id"] == "03384450"
    assert "ValueError" in record["error"]


def test_forecast_weights_are_causal_and_start_uniform():
    rng_free = np.linspace(0.0, 1.0, 60).reshape(4, 15)
    weights = forecast_log_weights(rng_free, 0.99)
    assert np.allclose(weights[:, 0], -np.log(4))
    mutated = rng_free.copy()
    mutated[:, 7:] = 99.0  # future evidence must not change weights at day 7
    assert np.allclose(
        forecast_log_weights(mutated, 0.99)[:, :8], weights[:, :8]
    )
    # and day t weights equal the posterior weights of day t-1
    assert np.allclose(weights[:, 1:], bma_log_weights(rng_free, 0.99)[:, :-1])


def test_mixture_forecast_matches_manual_mixture():
    loglik = np.array([[0.0, 2.0, 2.0], [0.0, 0.0, 0.0]])
    forecasts = np.array([[1.0, 1.0, 1.0], [3.0, 3.0, 3.0]])
    mixed = mixture_forecast(loglik, forecasts, None)
    assert mixed[0] == pytest.approx(2.0)  # uniform start: (1+3)/2
    w1 = np.exp(2.0) / (np.exp(2.0) + 1.0)
    assert mixed[2] == pytest.approx(w1 * 1.0 + (1 - w1) * 3.0)


def test_lockin_detector_requires_irreversibility():
    n, k = 900, 3
    base = np.full((n, k), 1.0 / 3.0)
    locked = base.copy()
    locked[500:, 0] = 0.9995
    locked[500:, 1:] = 0.00025
    assert detect_lockin(locked)
    released = locked.copy()
    released[880, 0] = 0.5  # dips below release after the long run
    released[880, 1] = 0.5 - 0.00025
    assert not detect_lockin(released)
    short = base.copy()
    short[500:500 + LOCKIN_DAYS - 1, 0] = 0.9995  # one day short of the rule
    assert not detect_lockin(short)


def test_boundary_cells_are_the_seven_m10_or_c04_cells():
    cells = grid_cells()
    boundary = boundary_cell_indices(cells)
    assert len(boundary) == 7
    for index in boundary:
        m, c = cells[index]
        assert m == 10.0 or c == 0.4
    # uniform weights over 15 cells keep the boundary share below the gate
    assert len(boundary) / len(cells) < BOUNDARY_WEIGHT_MAX


def test_cell_loader_rejects_truth_derived_fields(tmp_path):
    clean = tmp_path / "clean.npz"
    np.savez(clean, probabilities=np.zeros((3, 3)), observations=np.ones(3))
    loaded = _load_cell_npz(clean)
    assert set(loaded) == {"probabilities", "observations"}
    for key in sorted(TRUTH_KEYS):
        poisoned = tmp_path / f"poisoned_{key}.npz"
        np.savez(poisoned, probabilities=np.zeros((3, 3)),
                 **{key: np.zeros(3)})
        with pytest.raises(ValueError, match="forbidden"):
            _load_cell_npz(poisoned)


def test_arm_roster_is_frozen():
    assert ARMS == ("C", "P", "CTRL")
