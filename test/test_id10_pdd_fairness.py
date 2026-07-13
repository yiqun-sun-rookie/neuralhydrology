"""Fairness tests for the ID10 conceptual-model snow front ends."""
import os
import sys
import unittest

import numpy as np

_HERE = os.path.dirname(__file__)
_REPO_ROOT = os.path.abspath(os.path.join(_HERE, ".."))
_SRC_ROOT = os.path.join(_REPO_ROOT, "src")
for _p in (_REPO_ROOT, _SRC_ROOT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from src.xaj_global_pilot.gr4j_core import _snow_noice_step
from src.xaj_global_pilot.pdd_core import pdd_noice_step_mm, pdd_step
from src.xaj_global_pilot.xaj_numba import pdd_step_numba


NOICE_PARAMS = {
    "pdd_factor_snow": 4.2,
    "refreeze_snow": 0.17,
    "temp_snow": -1.5,
    "temp_rain": 2.8,
}

FULL_PARAMS_A = {
    **NOICE_PARAMS,
    "pdd_factor_ice": 1.0,
    "refreeze_ice": 0.0,
}

FULL_PARAMS_B = {
    **NOICE_PARAMS,
    "pdd_factor_ice": 15.0,
    "refreeze_ice": 0.5,
}

TEMP = np.array([-5.0, -1.0, 0.2, 1.5, 5.0, -0.5, 3.2], dtype=np.float64)
PREC = np.array([8.0, 12.0, 6.0, 0.0, 3.0, 10.0, 1.0], dtype=np.float64)


def _snow_fraction(temp: float, params: dict) -> float:
    frac = (params["temp_rain"] - temp) / (params["temp_rain"] - params["temp_snow"] + 1e-12)
    return min(1.0, max(0.0, frac))


def _run_full_pdd(params: dict):
    state = np.zeros((1, 3), dtype=np.float64)
    runoff = []
    snow_store = []
    ice_store = []
    for temp, prec in zip(TEMP, PREC):
        state, q = pdd_step(
            state,
            np.array([temp], dtype=np.float64),
            np.array([prec], dtype=np.float64),
            params,
        )
        runoff.append(float(q[0]))
        snow_store.append(float(state[0, 0]))
        ice_store.append(float(state[0, 1]))
    return np.array(runoff), np.array(snow_store), np.array(ice_store)


def _run_noice_reference(params: dict):
    snow_mm = 0.0
    runoff = []
    snow_store = []
    for temp, prec in zip(TEMP, PREC):
        snow_mm, liquid_mm = pdd_noice_step_mm(
            snow_mm,
            float(temp),
            float(prec),
            params["pdd_factor_snow"],
            params["refreeze_snow"],
            params["temp_snow"],
            params["temp_rain"],
        )
        runoff.append(liquid_mm)
        snow_store.append(snow_mm)
    return np.array(runoff), np.array(snow_store)


class TestPddFrontEndFairness(unittest.TestCase):
    def test_full_pdd_zero_ice_matches_noice_reference_and_ice_params_are_dead(self):
        noice_runoff_mm, noice_snow_mm = _run_noice_reference(NOICE_PARAMS)
        full_a_runoff_m, full_a_snow_m, full_a_ice_m = _run_full_pdd(FULL_PARAMS_A)
        full_b_runoff_m, full_b_snow_m, full_b_ice_m = _run_full_pdd(FULL_PARAMS_B)

        np.testing.assert_allclose(full_a_runoff_m * 1000.0, noice_runoff_mm, rtol=0.0, atol=1e-12)
        np.testing.assert_allclose(full_a_snow_m * 1000.0, noice_snow_mm, rtol=0.0, atol=1e-12)
        np.testing.assert_allclose(full_a_ice_m, 0.0, rtol=0.0, atol=0.0)

        np.testing.assert_allclose(full_b_runoff_m, full_a_runoff_m, rtol=0.0, atol=1e-15)
        np.testing.assert_allclose(full_b_snow_m, full_a_snow_m, rtol=0.0, atol=1e-15)
        np.testing.assert_allclose(full_b_ice_m, 0.0, rtol=0.0, atol=0.0)

    def test_gr4j_noice_step_matches_shared_noice_reference(self):
        snow_shared = 0.0
        snow_gr4j = 0.0
        for temp, prec in zip(TEMP, PREC):
            snow_shared, liquid_shared = pdd_noice_step_mm(
                snow_shared,
                float(temp),
                float(prec),
                NOICE_PARAMS["pdd_factor_snow"],
                NOICE_PARAMS["refreeze_snow"],
                NOICE_PARAMS["temp_snow"],
                NOICE_PARAMS["temp_rain"],
            )
            snow_gr4j, liquid_gr4j = _snow_noice_step(
                snow_gr4j,
                float(temp),
                float(prec),
                NOICE_PARAMS["pdd_factor_snow"],
                NOICE_PARAMS["refreeze_snow"],
                NOICE_PARAMS["temp_snow"],
                NOICE_PARAMS["temp_rain"],
            )
            self.assertAlmostEqual(snow_gr4j, snow_shared, places=12)
            self.assertAlmostEqual(liquid_gr4j, liquid_shared, places=12)

    def test_xaj_numba_pdd_zero_ice_matches_shared_noice_reference(self):
        state = np.zeros((1, 3), dtype=np.float64)
        snow_shared = 0.0
        for temp, prec in zip(TEMP, PREC):
            snow_shared, liquid_shared = pdd_noice_step_mm(
                snow_shared,
                float(temp),
                float(prec),
                NOICE_PARAMS["pdd_factor_snow"],
                NOICE_PARAMS["refreeze_snow"],
                NOICE_PARAMS["temp_snow"],
                NOICE_PARAMS["temp_rain"],
            )
            snow_frac = _snow_fraction(float(temp), NOICE_PARAMS)
            rain_t = np.array([prec * (1.0 - snow_frac)], dtype=np.float64)
            snow_t = np.array([prec * snow_frac], dtype=np.float64)
            state, runoff = pdd_step_numba(
                state,
                np.array([temp], dtype=np.float64),
                rain_t,
                snow_t,
                np.array([NOICE_PARAMS["pdd_factor_snow"]], dtype=np.float64),
                np.array([FULL_PARAMS_B["pdd_factor_ice"]], dtype=np.float64),
                np.array([NOICE_PARAMS["refreeze_snow"]], dtype=np.float64),
                np.array([FULL_PARAMS_B["refreeze_ice"]], dtype=np.float64),
            )
            self.assertAlmostEqual(float(runoff[0]), liquid_shared, places=12)
            self.assertAlmostEqual(float(state[0, 0]), snow_shared, places=12)
            self.assertEqual(float(state[0, 1]), 0.0)


if __name__ == "__main__":
    unittest.main()
