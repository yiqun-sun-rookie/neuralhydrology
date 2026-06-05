"""Sanity check for ``DifferentiableHBV96P1`` on 3 representative basins.

Picks one basin from each of {snow-dominated, humid, semi-arid/arid} regimes
where we already know XAJ-PDD's repro_v01 performance. Runs Adam multi-restart
calibration with the repro_v01 protocol periods and prints train+test NSE.

Usage::

    python -m scl_hydro.scripts.sanity_check_hbv96_p1
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_PROJECT_ROOT = _HERE.parents[2]
if str(_PROJECT_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT / "src"))

import numpy as np
import pandas as pd

from hydroagent.data_loading import load_camels_basin
from scl_hydro.hbv96_p1_calibrate import calibrate_hbv96_p1, simulate_hbv96_p1


# repro_v01 protocol (matches src/xaj_global_pilot/config.py)
CAL_START = "1999-10-01"
CAL_END   = "2008-09-30"
EVAL_START = "1989-10-01"
EVAL_END   = "1999-09-30"
FORCING = "maurer"

# 3 basins with known XAJ-PDD repro_v01 NSE for comparison
BASINS = [
    # (basin_id, regime_label, xaj_pdd_eval_nse_baseline)
    ("09035800", "snow-dominated",  0.814),   # XAJ-PDD did well here
    ("11481200", "humid",            0.757),   # XAJ-PDD also did well here
    ("06614800", "snow-dominated",   None),    # smoke_one default
    ("08104900", "semi-arid/arid",  -0.224),   # XAJ-PDD failed here (negative NSE)
]


def _nse(obs: np.ndarray, sim: np.ndarray) -> float:
    mask = np.isfinite(obs) & np.isfinite(sim)
    if mask.sum() < 10:
        return float("nan")
    o = obs[mask]
    s = sim[mask]
    denom = ((o - o.mean()) ** 2).sum()
    if denom < 1e-12:
        return float("nan")
    return float(1.0 - ((o - s) ** 2).sum() / denom)


def _run_one(basin_id: str, regime: str, xaj_baseline: float | None) -> dict:
    t0 = time.time()
    # ---- Calibration period ----
    forcing_cal, obs_cal, _ = load_camels_basin(
        basin_id, start_date=CAL_START, end_date=CAL_END, forcing=FORCING,
    )
    rain_cal = forcing_cal["prcp"].values.astype(np.float64)
    pet_col  = "ep" if "ep" in forcing_cal.columns else ("pet" if "pet" in forcing_cal.columns else None)
    if pet_col is None:
        raise RuntimeError(f"No PET column in forcing for {basin_id}")
    pet_cal  = forcing_cal[pet_col].values.astype(np.float64)
    temp_cal = forcing_cal["tmean"].values.astype(np.float64) if "tmean" in forcing_cal.columns else np.zeros_like(rain_cal)
    obs_cal_arr = obs_cal.values.astype(np.float64)

    result = calibrate_hbv96_p1(
        rain_cal, pet_cal, temp_cal, obs_cal_arr,
        n_epochs=120, lr=0.02, n_restarts=3, n_substep=2,
    )

    # ---- Evaluation period (with warm-started state) ----
    forcing_eval, obs_eval, _ = load_camels_basin(
        basin_id, start_date=EVAL_START, end_date=EVAL_END, forcing=FORCING,
    )
    rain_eval = forcing_eval["prcp"].values.astype(np.float64)
    pet_eval  = forcing_eval[pet_col].values.astype(np.float64)
    temp_eval = forcing_eval["tmean"].values.astype(np.float64) if "tmean" in forcing_eval.columns else np.zeros_like(rain_eval)
    obs_eval_arr = obs_eval.values.astype(np.float64)

    q_eval, _ = simulate_hbv96_p1(
        rain_eval, pet_eval, temp_eval,
        result["optimized_params"],
        state_init=result["final_state"],
        n_substep=2,
    )
    nse_eval = _nse(obs_eval_arr, q_eval)

    elapsed = time.time() - t0
    return {
        "basin_id":   basin_id,
        "regime":     regime,
        "xaj_baseline": xaj_baseline,
        "nse_cal":    result["nse"],
        "nse_eval":   nse_eval,
        "params":     result["optimized_params"],
        "elapsed_s":  elapsed,
    }


def main() -> int:
    print(f"=== HBV-96 P1 sanity check ({len(BASINS)} basins, repro_v01 protocol) ===")
    print(f"  Calibration: {CAL_START} → {CAL_END}")
    print(f"  Evaluation:  {EVAL_START} → {EVAL_END}")
    print(f"  Forcing:     {FORCING}")
    print()

    rows = []
    for basin_id, regime, xaj_baseline in BASINS:
        try:
            r = _run_one(basin_id, regime, xaj_baseline)
            baseline_str = f"{xaj_baseline:+.3f}" if xaj_baseline is not None else "  n/a "
            print(
                f"  {basin_id}  {regime:<16s}  "
                f"NSE_cal={r['nse_cal']:+.3f}  NSE_eval={r['nse_eval']:+.3f}  "
                f"(XAJ-PDD baseline: {baseline_str})  "
                f"[{r['elapsed_s']:.1f}s]"
            )
            rows.append(r)
        except Exception as exc:
            print(f"  {basin_id}  {regime:<16s}  FAILED: {exc}")

    print()
    if rows:
        eval_nses = [r["nse_eval"] for r in rows if np.isfinite(r["nse_eval"])]
        if eval_nses:
            print(f"Sanity median NSE_eval = {np.median(eval_nses):+.3f}  (n={len(eval_nses)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
