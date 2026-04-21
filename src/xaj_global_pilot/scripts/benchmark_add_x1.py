"""Supplement: add X1 (classical XAJ, no snow, 14 params) to the 15-basin benchmark."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
import warnings

warnings.filterwarnings("ignore", category=RuntimeWarning)

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from hydroagent.data_loading import load_camels_basin
from xaj_global_pilot.xaj_model import calibrate_xaj, simulate_xaj

TRAIN_START, TRAIN_END = "1990-10-01", "1995-09-30"
TEST_START, TEST_END = "2000-10-01", "2005-09-30"
N_TRIALS = 5000
N_RESTARTS = 3


def nse(obs, sim):
    mask = np.isfinite(obs) & np.isfinite(sim)
    if mask.sum() < 10:
        return np.nan
    o, s = obs[mask], sim[mask]
    d = np.sum((o - o.mean()) ** 2)
    return float(1.0 - np.sum((o - s) ** 2) / d) if d > 1e-12 else np.nan


def kge(obs, sim):
    mask = np.isfinite(obs) & np.isfinite(sim)
    if mask.sum() < 10:
        return np.nan
    o, s = obs[mask], sim[mask]
    r = np.corrcoef(o, s)[0, 1]
    alpha = np.std(s) / (np.std(o) + 1e-12)
    beta = np.mean(s) / (np.mean(o) + 1e-12)
    return float(1 - np.sqrt((r - 1) ** 2 + (alpha - 1) ** 2 + (beta - 1) ** 2))


def main():
    data_root = PROJECT_ROOT / "data" / "camels_us" / "full"
    csv_path = PROJECT_ROOT / "results" / "benchmark_conceptual_models_15basins.csv"
    df = pd.read_csv(csv_path, dtype={"basin": str})

    x1_train, x1_test_nse, x1_test_kge = [], [], []

    for _, row in df.iterrows():
        bid = row["basin"]
        regime = row["regime"]
        print(f"Basin {bid} ({regime})...", end=" ", flush=True)

        try:
            train_f, train_obs, _ = load_camels_basin(bid, data_root, TRAIN_START, TRAIN_END)
            test_f, test_obs, _ = load_camels_basin(bid, data_root, TEST_START, TEST_END)
        except Exception as e:
            print(f"DATA ERROR: {e}")
            x1_train.append(np.nan)
            x1_test_nse.append(np.nan)
            x1_test_kge.append(np.nan)
            continue

        t0 = time.time()
        try:
            result = calibrate_xaj(
                train_f["prcp"].values, train_f["ep"].values,
                train_obs.values, n_trials=N_TRIALS, n_restarts=N_RESTARTS,
            )
            params = result["optimized_params"]
            q_te, _ = simulate_xaj(test_f["prcp"].values, test_f["ep"].values, params)
            tr_nse = result["nse"]
            te_nse = nse(test_obs.values, q_te)
            te_kge = kge(test_obs.values, q_te)
            elapsed = time.time() - t0
            print(f"train={tr_nse:.4f}  test_NSE={te_nse:.4f}  test_KGE={te_kge:.4f}  ({elapsed:.0f}s)")
        except Exception as e:
            elapsed = time.time() - t0
            print(f"FAILED: {e}  ({elapsed:.0f}s)")
            tr_nse, te_nse, te_kge = np.nan, np.nan, np.nan

        x1_train.append(tr_nse)
        x1_test_nse.append(te_nse)
        x1_test_kge.append(te_kge)

    # Add to dataframe
    df["X1_XAJ_train_nse"] = x1_train
    df["X1_XAJ_test_nse"] = x1_test_nse
    df["X1_XAJ_test_kge"] = x1_test_kge

    # Save updated CSV
    df.to_csv(csv_path, index=False)
    print(f"\nUpdated {csv_path}")

    # Print summary
    models = ["H1_SfPy_HBV", "H2_NumPy_HBV", "H4_Sub4_HBV", "X1_XAJ", "X2_XAJ_PDD"]

    print(f"\n{'='*105}")
    print("UPDATED: MEDIAN TEST NSE BY REGIME (5 models)")
    print(f"{'='*105}")
    hdr = f"{'Regime':<12} {'n':>3}"
    for m in models:
        hdr += f" {m:>18}"
    print(hdr)
    print("-" * 105)
    for reg in ["snow", "humid", "semi-arid", "ALL"]:
        sub = df if reg == "ALL" else df[df.regime == reg]
        line = f"{reg:<12} {len(sub):>3}"
        for m in models:
            vals = sub[f"{m}_test_nse"].dropna()
            v = vals.median() if len(vals) > 0 else np.nan
            line += f" {v:>18.3f}" if np.isfinite(v) else f" {'N/A':>18}"
        print(line)


if __name__ == "__main__":
    main()
