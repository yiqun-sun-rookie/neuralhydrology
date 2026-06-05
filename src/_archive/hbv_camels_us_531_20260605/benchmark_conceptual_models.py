"""Benchmark 4 conceptual hydrological models on 15 CAMELS-US basins.

Fair comparison protocol:
  - 15 basins: 5 snow-dominated + 5 humid + 5 semi-arid
  - Stratified random sampling (seed=2026), NO performance filtering
  - Same calibration: 5000 evals x 3 restarts, 365-day warmup
  - Same periods: train 1990-10-01~1995-09-30, test 2000-10-01~2005-09-30

Models:
  H1 — SuperflexPy HBV  (implicit Euler, smooth ET+snow, 12 params)
  H2 — NumPy HBV        (explicit Euler dt=1, linear ET, 10 params)
  H4 — NumPy HBV+sub4   (explicit Euler dt=1/4, smooth ET+snow, 12 params)
  X2 — XAJ+PDD          (B-curve, 3-layer ET, PDD snow, 20 params)
"""
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
sys.path.insert(0, str(PROJECT_ROOT / "external" / "superflexpy"))

from hydroagent.data_loading import load_camels_basin
from hbv_camels_us_531.hbv_model import simulate_hbv, calibrate_hbv
from hbv_camels_us_531.structure import build_fixed_hbv_structure
from hydroagent.environment import SuperflexEnv
from xaj_global_pilot.xaj_model import calibrate_pdd_xaj, simulate_pdd_xaj

# =========================================================
# Constants
# =========================================================
TRAIN_START, TRAIN_END = "1990-10-01", "1995-09-30"
TEST_START, TEST_END = "2000-10-01", "2005-09-30"
N_TRIALS = 5000
N_RESTARTS = 3
WARMUP = 365
N_SUB = 4  # sub-steps for H4
SEED = 2026
N_PER_REGIME = 5


# =========================================================
# Basin selection: stratified random, no performance filter
# =========================================================
def select_basins(data_root: Path) -> pd.DataFrame:
    """Select N_PER_REGIME basins per regime via stratified random sampling."""
    topo = pd.read_csv(data_root / "camels_attributes_v2.0" / "camels_topo.txt",
                       sep=";", dtype={"gauge_id": str})
    clim = pd.read_csv(data_root / "camels_attributes_v2.0" / "camels_clim.txt",
                       sep=";", dtype={"gauge_id": str})
    attrs = topo.merge(clim, on="gauge_id")

    # Only use basins in 531 list (known to have complete data)
    basin_list = pd.read_csv(PROJECT_ROOT / "src" / "full_531_basins" / "data" / "531_basin_list.txt",
                             header=None, dtype=str)[0].tolist()
    attrs = attrs[attrs.gauge_id.isin(basin_list)].copy()

    # Classify
    attrs["regime"] = "humid"
    attrs.loc[attrs.frac_snow >= 0.2, "regime"] = "snow"
    attrs.loc[(attrs.frac_snow < 0.2) & (attrs.aridity > 1.0), "regime"] = "semi-arid"

    # Stratified random sample
    rng = np.random.RandomState(SEED)
    selected = []
    for regime in ["snow", "humid", "semi-arid"]:
        pool = attrs[attrs.regime == regime]
        idx = rng.choice(len(pool), size=min(N_PER_REGIME, len(pool)), replace=False)
        picked = pool.iloc[idx]
        selected.append(picked)

    result = pd.concat(selected, ignore_index=True)
    return result[["gauge_id", "regime", "frac_snow", "aridity", "elev_mean"]]


# =========================================================
# Metrics
# =========================================================
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


# =========================================================
# H1: SuperflexPy HBV (implicit Euler, 12 params)
# =========================================================
def run_h1(train_f, train_obs, test_f, test_obs):
    env = SuperflexEnv()
    env.parse_structure(build_fixed_hbv_structure())
    result = env.auto_calibrate(train_f, train_obs)

    env2 = SuperflexEnv()
    env2.parse_structure(build_fixed_hbv_structure())
    q_test = env2.run_simulation(test_f, result["optimized_params"]).values
    n = min(len(test_obs), len(q_test))
    return {
        "train_nse": result["nse"],
        "test_nse": nse(test_obs.values[:n], q_test[:n]),
        "test_kge": kge(test_obs.values[:n], q_test[:n]),
    }


# =========================================================
# H2: NumPy HBV (explicit Euler dt=1, 10 params)
# =========================================================
def run_h2(train_f, train_obs, test_f, test_obs):
    result = calibrate_hbv(
        train_f["prcp"].values, train_f["ep"].values, train_f["tmean"].values,
        train_obs.values, n_trials=N_TRIALS, n_restarts=N_RESTARTS,
    )
    q_test, _ = simulate_hbv(
        test_f["prcp"].values, test_f["ep"].values, test_f["tmean"].values,
        result["optimized_params"],
    )
    return {
        "train_nse": result["nse"],
        "test_nse": nse(test_obs.values, q_test),
        "test_kge": kge(test_obs.values, q_test),
    }


# =========================================================
# H4: NumPy HBV + substep dt=1/4 (smooth ET+snow, 12 params)
# =========================================================
H4_BOUNDS = {
    "t0": (-3.0, 3.0), "k_snow": (0.5, 5.0), "Smax": (50.0, 500.0),
    "Ce": (0.3, 1.5), "beta": (1.0, 5.0), "m_soil": (0.001, 0.5),
    "m_snow": (0.5, 10.0), "split": (0.1, 0.9),
    "k_fast": (0.001, 0.5), "alpha": (1.0, 3.0), "k_slow": (0.001, 0.1),
    "lag_time": (1.0, 10.0),
}


def _simulate_h4(rain, pet, temp, params):
    T = len(rain)
    t0, k_snow, Smax = params["t0"], params["k_snow"], params["Smax"]
    Ce, beta, m_soil = params["Ce"], params["beta"], params["m_soil"]
    m_snow, split = params["m_snow"], params["split"]
    k_fast, alpha, k_slow = params["k_fast"], params["alpha"], params["k_slow"]
    lag_time = params["lag_time"]
    dt = 1.0 / N_SUB

    S_snow, S_soil, S_fast, S_slow = 0.0, Smax * 0.3, 5.0, 5.0
    q_raw = np.zeros(T)

    for t in range(T):
        P_day, PET_day, Tm = rain[t], pet[t], temp[t]
        P_sub, PET_sub = P_day * dt, PET_day * dt
        q_day = 0.0
        for _ in range(N_SUB):
            snowfall = P_sub if Tm <= t0 else 0.0
            rainfall = P_sub - snowfall
            S_snow += snowfall
            mp = (k_snow * Tm * dt) if Tm > t0 else 0.0
            melt = mp * (1 - np.exp(-S_snow / (m_snow + 1e-12)))
            melt = max(min(melt, S_snow), 0.0)
            S_snow -= melt
            P_eff = rainfall + melt

            sr = min(max(S_soil / Smax, 0.0), 1.0)
            recharge = P_eff * (sr ** beta)
            aet = Ce * PET_sub * (sr * (1 + m_soil)) / (sr + m_soil + 1e-12)
            S_soil = max(min(S_soil + P_eff - recharge - aet, Smax), 0.0)

            qf = k_fast * dt * (S_fast ** alpha) if S_fast > 0 else 0.0
            qf = min(qf, S_fast + split * recharge)
            S_fast = max(S_fast + split * recharge - qf, 0.0)

            qs = k_slow * dt * S_slow
            qs = min(qs, S_slow + (1 - split) * recharge)
            S_slow = max(S_slow + (1 - split) * recharge - qs, 0.0)

            q_day += qf + qs
        q_raw[t] = q_day

    n = max(int(np.ceil(lag_time)), 1)
    w = np.arange(1, n + 1, dtype=np.float64)
    w /= w.sum()
    return np.convolve(q_raw, w, mode="full")[:T]


def run_h4(train_f, train_obs, test_f, test_obs):
    names = list(H4_BOUNDS.keys())
    lo = np.array([H4_BOUNDS[n][0] for n in names])
    hi = np.array([H4_BOUNDS[n][1] for n in names])
    ndim = len(names)
    r_tr = train_f["prcp"].values
    p_tr = train_f["ep"].values
    t_tr = train_f["tmean"].values
    obs_tr = train_obs.values
    warmup = min(WARMUP, len(obs_tr) // 4)

    def objective(x_norm):
        x = lo + np.clip(x_norm, 0, 1) * (hi - lo)
        params = dict(zip(names, x.tolist()))
        try:
            q = _simulate_h4(r_tr, p_tr, t_tr, params)
            v = nse(obs_tr[warmup:], q[warmup:])
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
    best_params = dict(zip(names, best_x.tolist()))
    q_tr = _simulate_h4(r_tr, p_tr, t_tr, best_params)
    train_nse_val = nse(obs_tr[warmup:], q_tr[warmup:])

    q_te = _simulate_h4(
        test_f["prcp"].values, test_f["ep"].values, test_f["tmean"].values, best_params
    )
    return {
        "train_nse": train_nse_val,
        "test_nse": nse(test_obs.values, q_te),
        "test_kge": kge(test_obs.values, q_te),
    }


# =========================================================
# X2: XAJ+PDD (B-curve, 3-layer ET, PDD snow, 20 params)
# =========================================================
def run_x2(train_f, train_obs, test_f, test_obs):
    r_tr = train_f["prcp"].values
    p_tr = train_f["ep"].values
    t_tr = train_f["tmean"].values
    result = calibrate_pdd_xaj(r_tr, p_tr, t_tr, train_obs.values, n_trials=N_TRIALS, n_restarts=N_RESTARTS)
    q_te, _ = simulate_pdd_xaj(
        test_f["prcp"].values, test_f["ep"].values, test_f["tmean"].values,
        result["optimized_params"],
    )
    return {
        "train_nse": result["nse"],
        "test_nse": nse(test_obs.values, q_te),
        "test_kge": kge(test_obs.values, q_te),
    }


# =========================================================
# Main
# =========================================================
MODELS = {
    "H1_SfPy_HBV": run_h1,
    "H2_NumPy_HBV": run_h2,
    "H4_Sub4_HBV": run_h4,
    "X2_XAJ_PDD": run_x2,
}


def main():
    data_root = PROJECT_ROOT / "data" / "camels_us" / "full"

    # --- Basin selection ---
    basins_df = select_basins(data_root)
    print("=" * 70)
    print(f"SELECTED BASINS ({len(basins_df)} total, seed={SEED})")
    print("=" * 70)
    for regime in ["snow", "humid", "semi-arid"]:
        sub = basins_df[basins_df.regime == regime]
        ids = ", ".join(sub.gauge_id.tolist())
        print(f"  {regime:<12} ({len(sub)}): {ids}")
    print()

    # --- Run all models on all basins ---
    all_results = []
    total_basins = len(basins_df)

    for i, (_, brow) in enumerate(basins_df.iterrows()):
        bid = brow.gauge_id
        regime = brow.regime
        print(f"\n{'='*70}")
        print(f"[{i+1}/{total_basins}] Basin {bid} ({regime})  "
              f"snow={brow.frac_snow:.2f}  aridity={brow.aridity:.2f}  elev={brow.elev_mean:.0f}m")
        print(f"{'='*70}")

        try:
            train_f, train_obs, area = load_camels_basin(bid, data_root, TRAIN_START, TRAIN_END)
            test_f, test_obs, _ = load_camels_basin(bid, data_root, TEST_START, TEST_END)
        except Exception as e:
            print(f"  DATA ERROR: {e}")
            continue

        print(f"  Train: {len(train_f)}d | Test: {len(test_f)}d | Area: {area:.0f} km2")

        row = {"basin": bid, "regime": regime, "frac_snow": brow.frac_snow,
               "aridity": brow.aridity, "elev_mean": brow.elev_mean}

        for mname, mfunc in MODELS.items():
            t0 = time.time()
            try:
                r = mfunc(train_f, train_obs, test_f, test_obs)
                elapsed = time.time() - t0
                print(f"  {mname:<16} train={r['train_nse']:.4f}  "
                      f"test_NSE={r['test_nse']:.4f}  test_KGE={r['test_kge']:.4f}  ({elapsed:.0f}s)")
                row[f"{mname}_train_nse"] = r["train_nse"]
                row[f"{mname}_test_nse"] = r["test_nse"]
                row[f"{mname}_test_kge"] = r["test_kge"]
            except Exception as e:
                elapsed = time.time() - t0
                print(f"  {mname:<16} FAILED: {e}  ({elapsed:.0f}s)")
                row[f"{mname}_train_nse"] = np.nan
                row[f"{mname}_test_nse"] = np.nan
                row[f"{mname}_test_kge"] = np.nan

        all_results.append(row)

    # =========================================================
    # Summary
    # =========================================================
    df = pd.DataFrame(all_results)

    print(f"\n\n{'='*100}")
    print("TEST NSE — ALL BASINS")
    print(f"{'='*100}")
    hdr = f"{'Basin':<12} {'Regime':<12} {'Snow':>5} {'Arid':>5}"
    for m in MODELS:
        hdr += f" {m:>16}"
    print(hdr)
    print("-" * (34 + 17 * len(MODELS)))
    for _, r in df.iterrows():
        line = f"{r['basin']:<12} {r['regime']:<12} {r['frac_snow']:>5.2f} {r['aridity']:>5.2f}"
        for m in MODELS:
            v = r.get(f"{m}_test_nse", np.nan)
            line += f" {v:>16.4f}" if np.isfinite(v) else f" {'FAIL':>16}"
        print(line)

    print("-" * (34 + 17 * len(MODELS)))
    for stat_name, stat_func in [("Median", "median"), ("Mean", "mean")]:
        line = f"{stat_name:<12} {'':12} {'':>5} {'':>5}"
        for m in MODELS:
            vals = df[f"{m}_test_nse"].dropna()
            v = getattr(vals, stat_func)() if len(vals) > 0 else np.nan
            line += f" {v:>16.4f}" if np.isfinite(v) else f" {'N/A':>16}"
        print(line)

    # By regime
    print(f"\n{'='*100}")
    print("MEDIAN TEST NSE BY REGIME")
    print(f"{'='*100}")
    hdr = f"{'Regime':<12} {'n':>3}"
    for m in MODELS:
        hdr += f" {m:>16}"
    print(hdr)
    print("-" * (15 + 17 * len(MODELS)))
    for regime in ["snow", "humid", "semi-arid"]:
        sub = df[df.regime == regime]
        line = f"{regime:<12} {len(sub):>3}"
        for m in MODELS:
            vals = sub[f"{m}_test_nse"].dropna()
            v = vals.median() if len(vals) > 0 else np.nan
            line += f" {v:>16.4f}" if np.isfinite(v) else f" {'N/A':>16}"
        print(line)

    # KGE summary
    print(f"\n{'='*100}")
    print("MEDIAN TEST KGE BY REGIME")
    print(f"{'='*100}")
    hdr = f"{'Regime':<12} {'n':>3}"
    for m in MODELS:
        hdr += f" {m:>16}"
    print(hdr)
    print("-" * (15 + 17 * len(MODELS)))
    for regime in ["snow", "humid", "semi-arid"]:
        sub = df[df.regime == regime]
        line = f"{regime:<12} {len(sub):>3}"
        for m in MODELS:
            vals = sub[f"{m}_test_kge"].dropna()
            v = vals.median() if len(vals) > 0 else np.nan
            line += f" {v:>16.4f}" if np.isfinite(v) else f" {'N/A':>16}"
        print(line)

    # Save
    out_csv = PROJECT_ROOT / "results" / "benchmark_conceptual_models_15basins.csv"
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out_csv, index=False)
    print(f"\nResults saved to {out_csv}")


if __name__ == "__main__":
    main()
