"""Supplement: add X2s (XAJ+PDD with sub-step dt=1/4) to the 15-basin benchmark."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
import cma
import warnings

warnings.filterwarnings("ignore", category=RuntimeWarning)

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from hydroagent.data_loading import load_camels_basin
from xaj_global_pilot.xaj_numba import coupled_pdd_xaj_step_numba
from xaj_global_pilot.xaj_model import PDD_PARAM_BOUNDS, PARAM_BOUNDS

TRAIN_START, TRAIN_END = "1990-10-01", "1995-09-30"
TEST_START, TEST_END = "2000-10-01", "2005-09-30"
N_TRIALS = 5000
N_RESTARTS = 3
WARMUP = 365
N_SUB = 4


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
    beta_v = np.mean(s) / (np.mean(o) + 1e-12)
    return float(1 - np.sqrt((r - 1) ** 2 + (alpha - 1) ** 2 + (beta_v - 1) ** 2))


def simulate_pdd_xaj_sub(rain, pet, temp, params, n_sub=N_SUB):
    """XAJ+PDD with sub-stepped explicit Euler."""
    T = len(rain)
    dt = 1.0 / n_sub

    wm = params['wum'] + params['wlm'] + params['wdm']
    wmm = wm * (1 + params['b']) / (1 - params['imp'])
    ms = params['sm'] * (1 + params['ex'])

    # Adjust recession coefficients for sub-timestep:
    # Daily: Q_new = cs * Q_old + (1-cs) * R
    # Sub-step: cs_sub = cs^(1/n_sub) so that cs_sub^n_sub = cs
    cs_sub = params['cs'] ** dt
    ci_sub = params['ci'] ** dt
    cg_sub = params['cg'] ** dt

    xaj_pars = tuple(np.array([np.float64(v)]) for v in (
        params['kc'], params['ki'], params['kg'],
        cs_sub, ci_sub, cg_sub,
        params['wum'], params['wlm'], params['wdm'],
        params['sm'], params['imp'], params['c'],
        params['b'], params['ex'], 1.0, wmm, ms,  # uf=1.0, not dt
    ))

    pdd_pars = tuple(np.array([np.float64(params[k])]) for k in (
        'pdd_factor_snow', 'pdd_factor_ice', 'refreeze_snow', 'refreeze_ice'))

    temp_snow = params.get('temp_snow', 0.0)
    temp_rain = params.get('temp_rain', 2.0)

    state = np.array([[
        0.0, 0.0, 0.0,
        params['wum'] * 0.5 + params['wlm'] * 0.5 + params['wdm'] * 0.5,
        params['wum'] * 0.5, params['wlm'] * 0.5, params['wdm'] * 0.5,
        params['sm'] * 0.5, 0.0, 0.0, 0.0,
    ]])

    q = np.zeros(T)
    for t in range(T):
        t_val = temp[t]
        snow_frac = np.clip((temp_rain - t_val) / (temp_rain - temp_snow + 1e-12), 0.0, 1.0)

        # Divide daily forcing across sub-steps
        snow_sub = np.array([rain[t] * snow_frac * dt])
        rain_sub = np.array([rain[t] * (1.0 - snow_frac) * dt])
        pet_sub = np.array([pet[t] * dt])
        temp_sub = np.array([t_val])

        q_day = 0.0
        for _ in range(n_sub):
            state, _ = coupled_pdd_xaj_step_numba(
                state, temp_sub, rain_sub, snow_sub, pet_sub, pdd_pars, xaj_pars)
            q_day += state[0, 8] + state[0, 9] + state[0, 10]

        q[t] = q_day

    return np.maximum(q, 0.0), state.copy()


ALL_BOUNDS = {**PARAM_BOUNDS, **PDD_PARAM_BOUNDS}
PARAM_NAMES = list(ALL_BOUNDS.keys())


def calibrate_pdd_xaj_sub(rain, pet, temp, obs):
    lo = np.array([ALL_BOUNDS[n][0] for n in PARAM_NAMES])
    hi = np.array([ALL_BOUNDS[n][1] for n in PARAM_NAMES])
    ndim = len(PARAM_NAMES)
    warmup = min(WARMUP, len(obs) // 4)

    def objective(x_norm):
        x = lo + np.clip(x_norm, 0, 1) * (hi - lo)
        params = dict(zip(PARAM_NAMES, x.tolist()))
        if params['ki'] + params['kg'] > 0.7:
            return 2.0
        try:
            q, _ = simulate_pdd_xaj_sub(rain, pet, temp, params)
            v = nse(obs[warmup:], q[warmup:])
            return 1.0 - v if np.isfinite(v) else 2.0
        except Exception:
            return 2.0

    best = None
    for restart in range(N_RESTARTS):
        es = cma.CMAEvolutionStrategy([0.5] * ndim, 0.3, {
            "bounds": [[0.0] * ndim, [1.0] * ndim],
            "maxfevals": N_TRIALS, "seed": 42 + restart * 1000, "verbose": -9,
        })
        es.optimize(objective)
        if best is None or es.result.fbest < best[1]:
            best = (es.result.xbest.copy(), es.result.fbest)

    best_x = lo + np.clip(best[0], 0, 1) * (hi - lo)
    best_params = dict(zip(PARAM_NAMES, best_x.tolist()))
    q_tr, _ = simulate_pdd_xaj_sub(rain, pet, temp, best_params)
    train_nse = nse(obs[warmup:], q_tr[warmup:])
    return {"optimized_params": best_params, "nse": train_nse}


def main():
    data_root = PROJECT_ROOT / "data" / "camels_us" / "full"
    csv_path = PROJECT_ROOT / "results" / "benchmark_conceptual_models_15basins.csv"
    df = pd.read_csv(csv_path, dtype={"basin": str})

    x2s_train, x2s_test_nse, x2s_test_kge = [], [], []

    for _, row in df.iterrows():
        bid = row["basin"]
        regime = row["regime"]
        print(f"Basin {bid} ({regime})...", end=" ", flush=True)

        try:
            train_f, train_obs, _ = load_camels_basin(bid, data_root, TRAIN_START, TRAIN_END)
            test_f, test_obs, _ = load_camels_basin(bid, data_root, TEST_START, TEST_END)
        except Exception as e:
            print(f"DATA ERROR: {e}")
            x2s_train.append(np.nan); x2s_test_nse.append(np.nan); x2s_test_kge.append(np.nan)
            continue

        t0 = time.time()
        try:
            result = calibrate_pdd_xaj_sub(
                train_f["prcp"].values, train_f["ep"].values, train_f["tmean"].values,
                train_obs.values,
            )
            params = result["optimized_params"]
            q_te, _ = simulate_pdd_xaj_sub(
                test_f["prcp"].values, test_f["ep"].values, test_f["tmean"].values, params
            )
            tr = result["nse"]
            te_nse = nse(test_obs.values, q_te)
            te_kge = kge(test_obs.values, q_te)
            elapsed = time.time() - t0
            print(f"train={tr:.4f}  test_NSE={te_nse:.4f}  test_KGE={te_kge:.4f}  ({elapsed:.0f}s)")
        except Exception as e:
            elapsed = time.time() - t0
            print(f"FAILED: {e}  ({elapsed:.0f}s)")
            tr, te_nse, te_kge = np.nan, np.nan, np.nan

        x2s_train.append(tr); x2s_test_nse.append(te_nse); x2s_test_kge.append(te_kge)

    df["X2s_XAJ_PDD_Sub4_train_nse"] = x2s_train
    df["X2s_XAJ_PDD_Sub4_test_nse"] = x2s_test_nse
    df["X2s_XAJ_PDD_Sub4_test_kge"] = x2s_test_kge
    df.to_csv(csv_path, index=False)
    print(f"\nUpdated {csv_path}")

    # Summary: compare X2 vs X2s
    models = ["H1_SfPy_HBV", "H2_NumPy_HBV", "H4_Sub4_HBV", "X2_XAJ_PDD", "X2s_XAJ_PDD_Sub4"]
    print(f"\n{'='*110}")
    print("MEDIAN TEST NSE BY REGIME (with XAJ+PDD sub-step)")
    print(f"{'='*110}")
    hdr = f"{'Regime':<12} {'n':>3}"
    for m in models:
        hdr += f" {m:>19}"
    print(hdr)
    print("-" * 110)
    for reg in ["snow", "humid", "semi-arid", "ALL"]:
        sub = df if reg == "ALL" else df[df.regime == reg]
        line = f"{reg:<12} {len(sub):>3}"
        for m in models:
            vals = sub[f"{m}_test_nse"].dropna()
            v = vals.median() if len(vals) > 0 else np.nan
            line += f" {v:>19.3f}" if np.isfinite(v) else f" {'N/A':>19}"
        print(line)


if __name__ == "__main__":
    main()
