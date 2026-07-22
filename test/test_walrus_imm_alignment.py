"""Tests for the WALRUS fixed-step port used by the cross-code IMM alignment.

Oracles are deliberately independent of the implementation: closed-form
identities, the official WALRUS R-package algebraic form (which differs
symbolically from the audited MATLAB form), and hand-computed constants.
"""

import math
import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from hbv_multilead_joint_uncertainty.walrus_port import (  # noqa: E402
    beta_dv,
    dveq_dg,
    etv_ets_etact,
    pond_flood,
    pq_pv_ps,
    q_hs,
    statetran,
    w_dv,
    walrus_st_sp,
)


B_SOIL = 4.38
PSI_AE = 90.0
THETA_S = 0.41


def _dveq_r_form(x: float) -> float:
    """Official WALRUS R-package formula (WALRUS_defaults.R), symbolically
    distinct from the MATLAB form used in the implementation."""
    if x > PSI_AE:
        return (
            x
            - PSI_AE / (1.0 - B_SOIL)
            - x * (x / PSI_AE) ** (-1.0 / B_SOIL)
            + PSI_AE / (1.0 - B_SOIL) * (x / PSI_AE) ** (1.0 - 1.0 / B_SOIL)
        ) * THETA_S
    if x < 0.0:
        return x
    return 0.0


class TestWetnessIndex:
    def test_endpoints_and_midpoint(self):
        assert w_dv(0.0, 400.0) == pytest.approx(1.0, abs=1e-15)
        assert w_dv(400.0, 400.0) == pytest.approx(0.0, abs=1e-15)
        assert w_dv(200.0, 400.0) == pytest.approx(0.5, abs=1e-15)

    def test_clamped_outside_bounds(self):
        assert w_dv(-5.0, 400.0) == pytest.approx(1.0, abs=1e-15)
        assert w_dv(410.0, 400.0) == pytest.approx(0.0, abs=1e-15)

    def test_quarter_point(self):
        assert w_dv(100.0, 400.0) == pytest.approx(0.5 * math.cos(math.pi / 4.0) + 0.5, rel=1e-15)


class TestEquilibriumStorage:
    def test_negative_groundwater_depth_passthrough(self):
        assert dveq_dg(-3.0) == pytest.approx(-3.0, abs=0.0)

    def test_shallow_zone_zero(self):
        assert dveq_dg(0.0) == 0.0
        assert dveq_dg(50.0) == 0.0
        assert dveq_dg(PSI_AE) == 0.0

    @pytest.mark.parametrize("dg", [90.001, 150.0, 500.0, 1000.0, 2400.0])
    def test_matches_official_r_form_above_air_entry(self, dg):
        assert dveq_dg(dg) == pytest.approx(_dveq_r_form(dg), rel=1e-12)


class TestEvaporationReduction:
    def test_center_is_half(self):
        assert beta_dv(400.0) == pytest.approx(0.5, abs=1e-15)

    def test_at_zero_storage_deficit(self):
        assert beta_dv(0.0) == pytest.approx(0.5 * math.tanh(4.0) + 0.5, rel=1e-14)

    def test_wet_limit_approaches_one(self):
        assert beta_dv(-2000.0) == pytest.approx(1.0, abs=1e-12)


class TestStageDischarge:
    def test_below_weir_is_zero(self):
        assert q_hs(0.0, 0.2, 2450.0) == 0.0
        assert q_hs(-5.0, 0.2, 2450.0) == 0.0

    def test_bankfull_equals_cs(self):
        assert q_hs(2450.0, 0.2, 2450.0) == pytest.approx(0.2, rel=1e-15)

    def test_power_law_halfway(self):
        assert q_hs(1225.0, 0.2, 2450.0) == pytest.approx(0.2 * 0.5**1.5, rel=1e-14)

    def test_above_bankfull_extension(self):
        expected = 0.2 + 0.2 * (10.0 / 2450.0) ** 1.5
        assert q_hs(2460.0, 0.2, 2450.0) == pytest.approx(expected, rel=1e-14)


class TestRainfallSplit:
    def test_partition_sums_to_precipitation(self):
        pq, pv, ps = pq_pv_ps(10.0, 0.3)
        assert pq == pytest.approx(10.0 * 0.3 * 0.99, rel=1e-15)
        assert pv == pytest.approx(10.0 * 0.7 * 0.99, rel=1e-15)
        assert ps == pytest.approx(0.1, rel=1e-15)
        assert pq + pv + ps == pytest.approx(10.0, rel=1e-14)


class TestEvapotranspirationSplit:
    def test_partition_with_wet_channel(self):
        etv, ets, etact = etv_ets_etact(2.0, 400.0, 500.0)
        assert etv == pytest.approx(2.0 * 0.5 * 0.99, rel=1e-14)
        assert ets == pytest.approx(0.02, rel=1e-15)
        assert etact == pytest.approx(etv + ets, rel=1e-15)

    def test_dry_channel_suppresses_open_water_evaporation(self):
        _, ets, _ = etv_ets_etact(2.0, 400.0, 0.5)
        assert ets == 0.0


class TestPondFlood:
    def test_ponding_only(self):
        dv, hs, dg = pond_flood(-2.0, 100.0, 800.0, 2450.0)
        assert hs == pytest.approx(100.0 + 2.0 * 0.99 / 0.01, rel=1e-15)
        assert dv == 0.0
        assert dg == 800.0

    def test_flooding_only(self):
        dv, hs, dg = pond_flood(50.0, 2460.0, 800.0, 2450.0)
        assert dv == pytest.approx(50.0 - 10.0 * 0.01 / 0.99, rel=1e-14)
        assert hs == 2450.0
        assert dg == 800.0

    def test_ponding_and_flooding_sets_groundwater_to_pond_level(self):
        dv, hs, dg = pond_flood(-2.0, 2460.0, 800.0, 2450.0)
        expected_dv = -2.0 * 0.99 - 10.0 * 0.01
        assert dv == pytest.approx(expected_dv, rel=1e-14)
        assert hs == pytest.approx(2450.0 - expected_dv, rel=1e-14)
        assert dg == pytest.approx(expected_dv, rel=1e-14)

    def test_no_trigger_passthrough(self):
        assert pond_flood(140.0, 1200.0, 1000.0, 2450.0) == (140.0, 1200.0, 1000.0)


class TestFullStep:
    STATE0 = np.array([140.0, 1000.0, 4.0, 1200.0, 0.15])
    PARAMS = dict(cw=600.0, cv=50.0, cg=1.8e7, cq=6.0, cd=2450.0, cs=0.2)

    def test_shapes_and_finiteness(self):
        out = walrus_st_sp(self.STATE0, p_t=0.5, etpot_t=0.1, **self.PARAMS)
        assert out.shape == (5,)
        assert np.all(np.isfinite(out))

    def test_discharge_state_evaluated_from_new_stage(self):
        out = walrus_st_sp(self.STATE0, p_t=0.0, etpot_t=0.0, **self.PARAMS)
        dv0, dg0, hq0, hs0, q0 = self.STATE0
        fqs = hq0 / self.PARAMS["cq"]
        fgs = (
            (self.PARAMS["cd"] - dg0 - hs0)
            * max(self.PARAMS["cd"] - dg0, hs0)
            / self.PARAMS["cg"]
        )
        etv, ets, _ = etv_ets_etact(0.0, dv0, hs0)
        hs_new = hs0 + (0.0 + 0.0 - ets + fgs + fqs - q0) / 0.01
        assert out[4] == pytest.approx(q_hs(hs_new, self.PARAMS["cs"], self.PARAMS["cd"]), rel=1e-12)

    def test_negative_stage_guard_uses_official_emergency_value(self):
        state = np.array([140.0, 1000.0, 4.0, 0.0, 5.0])
        out = walrus_st_sp(state, p_t=0.0, etpot_t=0.0, **self.PARAMS)
        assert out[3] == pytest.approx(0.1, abs=0.0)

    def test_discharge_never_negative(self):
        state = np.array([140.0, 1000.0, 4.0, -50.0, -3.0])
        out = walrus_st_sp(state, p_t=0.0, etpot_t=0.0, **self.PARAMS)
        assert out[4] >= 0.0


class TestStatetranWrapper:
    PARAMS = dict(cw=600.0, cv=50.0, cg=1.8e7, cq=6.0, cd=2450.0, cs=0.2)

    def test_noise_added_after_model_step(self):
        state = np.array([140.0, 1000.0, 4.0, 1200.0, 0.15])
        base = statetran(state, 0.5, 0.1, np.zeros(5), **self.PARAMS)
        noise = np.array([1.0, -2.0, 0.5, 3.0, 0.01])
        shifted = statetran(state, 0.5, 0.1, noise, **self.PARAMS)
        np.testing.assert_allclose(shifted, base + noise, rtol=0.0, atol=1e-12)

    def test_wrapper_guard_repairs_noise_driven_negative_stage(self):
        state = np.array([140.0, 1000.0, 4.0, 1200.0, 0.15])
        base = statetran(state, 0.5, 0.1, np.zeros(5), **self.PARAMS)
        noise = np.zeros(5)
        noise[3] = -(base[3] + 5.0)
        out = statetran(state, 0.5, 0.1, noise, **self.PARAMS)
        assert out[3] == pytest.approx(0.1, abs=0.0)

    def test_wrapper_guard_elseif_skips_quickflow_when_stage_repaired(self):
        state = np.array([140.0, 1000.0, 4.0, 1200.0, 0.15])
        base = statetran(state, 0.5, 0.1, np.zeros(5), **self.PARAMS)
        noise = np.zeros(5)
        noise[3] = -(base[3] + 5.0)
        noise[2] = -(base[2] + 5.0)
        out = statetran(state, 0.5, 0.1, noise, **self.PARAMS)
        assert out[3] == pytest.approx(0.1, abs=0.0)
        assert out[2] == pytest.approx(base[2] + noise[2], rel=1e-12)
