"""Bit-exact self-check for the HBV-lite ``--bounds-preset`` runtime threading (S2).

Goal: prove that selecting bounds at RUNTIME via
``resolve_hbv_bounds(preset)`` + ``calibrate_hbv_lite_cma(param_bounds=...)``
is a faithful no-op relative to the old import-time ``HBV_BOUNDS`` env
mechanism, and that the preset actually switches the search space.

Three checks::

  1. ``resolve_hbv_bounds("v1")`` deep-equals the module ``_BOUNDS_V1``
     (hydroDL2 literature-tight); ``"v5"`` deep-equals ``_BOUNDS_V5`` (wide);
     an unknown preset raises ``ValueError``.
  2. With the module-default bounds, ``calibrate(param_bounds=None)`` ==
     ``calibrate(param_bounds=resolve_hbv_bounds(<the module default>))``
     BIT-EXACT (params and NSE) — the threading does not perturb anything.
  3. ``calibrate(param_bounds=resolve_hbv_bounds("v1"))`` differs from the
     ``"v5"`` result — the preset genuinely changes the calibration bounds.

Run::

    python -X utf8 -m src.scl_hydro.scripts.verify_hbv_bounds_preset

Exit 0 = PASS, 1 = FAIL.
"""
from __future__ import annotations

import sys
from pathlib import Path

_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[3]
if str(_REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT / "src"))
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

import numpy as np  # noqa: E402

from hydroagent.data_loading import load_camels_basin  # noqa: E402
from scl_hydro.hbv_lite_numpy import (  # noqa: E402
    _BOUNDS_V1,
    _BOUNDS_V5,
    PARAM_BOUNDS,
    PARAM_NAMES,
    resolve_hbv_bounds,
)
from scl_hydro.hbv_lite_cma_calibrate import calibrate_hbv_lite_cma  # noqa: E402

BASIN = "01022500"
CAL = ("1999-10-01", "2008-09-30")
TRIALS, RESTARTS = 400, 1  # bit-exactness is seed-driven, not budget-driven


def _load(basin: str, pet_method: str = "priestley_taylor"):
    forcing, obs, _ = load_camels_basin(
        basin, data_root="data/camels_us",
        start_date=CAL[0], end_date=CAL[1], forcing="maurer", pet_method=pet_method,
    )
    rain = forcing["prcp"].values.astype(np.float64)
    pet_col = "ep" if "ep" in forcing.columns else "pet"
    pet = forcing[pet_col].values.astype(np.float64)
    temp = (forcing["tmean"].values.astype(np.float64)
            if "tmean" in forcing.columns else np.zeros_like(rain))
    return rain, pet, temp, obs.values.astype(np.float64)


def _pvec(res: dict) -> np.ndarray:
    return np.array([res["optimized_params"][n] for n in PARAM_NAMES], dtype=np.float64)


def main() -> int:
    # --- check 1: resolver correctness -----------------------------------
    if resolve_hbv_bounds("v1") != {k: tuple(v) for k, v in _BOUNDS_V1.items()}:
        print("FAIL[1]: resolve_hbv_bounds('v1') != _BOUNDS_V1")
        return 1
    if resolve_hbv_bounds("v5") != {k: tuple(v) for k, v in _BOUNDS_V5.items()}:
        print("FAIL[1]: resolve_hbv_bounds('v5') != _BOUNDS_V5")
        return 1
    try:
        resolve_hbv_bounds("does_not_exist")
        print("FAIL[1]: unknown preset did not raise ValueError")
        return 1
    except ValueError:
        pass
    default_key = "v1" if PARAM_BOUNDS == _BOUNDS_V1 else "v5"
    print(f"[1/3] resolver OK; module default PARAM_BOUNDS == {default_key}")

    rain, pet, temp, obs = _load(BASIN)

    # --- check 2: faithful threading (param_bounds=None == module default)
    res_none = calibrate_hbv_lite_cma(
        rain, pet, temp, obs, n_trials=TRIALS, n_restarts=RESTARTS, param_bounds=None)
    res_modeq = calibrate_hbv_lite_cma(
        rain, pet, temp, obs, n_trials=TRIALS, n_restarts=RESTARTS,
        param_bounds=resolve_hbv_bounds(default_key))
    dparam = float(np.abs(_pvec(res_none) - _pvec(res_modeq)).sum())
    dnse = abs(res_none["nse"] - res_modeq["nse"])
    print(f"[2/3] faithful threading: |Δparams|={dparam:.3e}  |Δnse|={dnse:.3e}")
    if dparam != 0.0 or dnse != 0.0:
        print("FAIL[2]: param_bounds threading is NOT bit-exact vs module default")
        return 1

    # --- check 3: preset actually switches the search space ---------------
    res_v1 = calibrate_hbv_lite_cma(
        rain, pet, temp, obs, n_trials=TRIALS, n_restarts=RESTARTS,
        param_bounds=resolve_hbv_bounds("v1"))
    res_v5 = calibrate_hbv_lite_cma(
        rain, pet, temp, obs, n_trials=TRIALS, n_restarts=RESTARTS,
        param_bounds=resolve_hbv_bounds("v5"))
    d15 = float(np.abs(_pvec(res_v1) - _pvec(res_v5)).sum())
    print(f"[3/3] v1 vs v5 differ: |Δparams|={d15:.3e}  (expect > 0)")
    if d15 == 0.0:
        print("FAIL[3]: v1 and v5 gave identical params — preset not switching bounds")
        return 1

    print("PASS: --bounds-preset runtime threading is bit-exact and effective.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
