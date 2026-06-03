"""Sanity check for ``DifferentiableHBVLite`` on 4 representative basins.

Mirrors ``sanity_check_hbv96_p1.py`` but uses the HBV-light port.
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

# Single thread for fairness with other concurrent work
for _v in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ.setdefault(_v, "1")
import torch
torch.set_num_threads(1)

import numpy as np
import pandas as pd

from hydroagent.data_loading import load_camels_basin
from scl_hydro.hbv_lite_calibrate import calibrate_hbv_lite, simulate_hbv_lite


CAL_START = "1999-10-01"
CAL_END   = "2008-09-30"
EVAL_START = "1989-10-01"
EVAL_END   = "1999-09-30"
FORCING = "maurer"

BASINS = [
    ("09035800", "snow-dominated",  0.814),   # XAJ-PDD broken-PET baseline
    ("11481200", "humid",            0.794),
    ("06614800", "snow-dominated",   0.837),
    ("08104900", "semi-arid/arid",   0.455),
]

N_EPOCHS = 200
N_RESTARTS = 3
LR = 0.02


def _nse(obs, sim):
    m = np.isfinite(obs) & np.isfinite(sim)
    if m.sum() < 10:
        return float("nan")
    o, s = obs[m], sim[m]
    denom = ((o - o.mean()) ** 2).sum()
    if denom < 1e-12:
        return float("nan")
    return float(1.0 - ((o - s) ** 2).sum() / denom)


def _run_one(basin_id, regime, xaj_baseline):
    t0 = time.time()
    fc_c, oc_c, _ = load_camels_basin(basin_id, start_date=CAL_START, end_date=CAL_END, forcing=FORCING)
    rain_c = fc_c["prcp"].values.astype(np.float64)
    pet_c  = fc_c["ep"].values.astype(np.float64)
    temp_c = fc_c["tmean"].values.astype(np.float64)
    obs_c  = oc_c.values.astype(np.float64)

    r = calibrate_hbv_lite(rain_c, pet_c, temp_c, obs_c,
                            n_epochs=N_EPOCHS, lr=LR, n_restarts=N_RESTARTS)

    fc_e, oc_e, _ = load_camels_basin(basin_id, start_date=EVAL_START, end_date=EVAL_END, forcing=FORCING)
    rain_e = fc_e["prcp"].values.astype(np.float64)
    pet_e  = fc_e["ep"].values.astype(np.float64)
    temp_e = fc_e["tmean"].values.astype(np.float64)
    obs_e  = oc_e.values.astype(np.float64)

    q_e, _ = simulate_hbv_lite(rain_e, pet_e, temp_e, r["optimized_params"],
                                state_init=r["final_state"])
    nse_e = _nse(obs_e[365:], q_e[365:])
    return {
        "basin_id": basin_id, "regime": regime, "xaj_baseline": xaj_baseline,
        "nse_cal": r["nse"], "nse_eval": nse_e,
        "params": r["optimized_params"], "elapsed_s": time.time() - t0,
    }


def main():
    print(f"=== HBV-lite sanity (4 basins, repro_v01) ===")
    print(f"  config: n_epochs={N_EPOCHS}, n_restarts={N_RESTARTS}, lr={LR}")
    print()

    rows = []
    for basin_id, regime, xaj in BASINS:
        try:
            r = _run_one(basin_id, regime, xaj)
            baseline_str = f"{xaj:+.3f}" if xaj is not None else "  n/a "
            print(f"  {r['basin_id']}  {r['regime']:<16s}  "
                  f"NSE_cal={r['nse_cal']:+.3f}  NSE_eval={r['nse_eval']:+.3f}  "
                  f"(XAJ-PDD baseline: {baseline_str})  [{r['elapsed_s']:.0f}s]",
                  flush=True)
            rows.append(r)
        except Exception as exc:
            print(f"  {basin_id}  {regime:<16s}  FAILED: {exc}", flush=True)

    print()
    eval_nses = [r["nse_eval"] for r in rows if np.isfinite(r["nse_eval"])]
    if eval_nses:
        median = float(np.median(eval_nses))
        mean   = float(np.mean(eval_nses))
        print(f"Sanity median NSE_eval = {median:+.3f}  mean = {mean:+.3f}  (n={len(eval_nses)})", flush=True)
        if median >= 0.6:
            print(f"  ✓ TARGET MET (≥ 0.6)", flush=True)
        elif median >= 0.55:
            print(f"  ~ TARGET CLOSE (0.55-0.60)", flush=True)
        else:
            print(f"  ✗ TARGET MISS (< 0.55), iterate", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
