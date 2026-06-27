"""Train the 002_hybrid concept-state GBM (XGBoost) for Track-0.

Hybrid physics-ML, conceptual-state feature injection (published approach class:
Frame 2021 / Konapala 2020 LSTM post-processing of conceptual models; the GPU
cousin is differentiable dPL / delta-HBV, Feng & Shen 2022/23). Here a calibrated
GR4J-PDD conceptual model supplies adaptive nonlinear catchment-memory STATE
trajectories as extra features for a single global gradient-boosted tree.

Pipeline (train side -- allowed to read TRAIN-period observed discharge):
  1. Reuse the per-basin GR4J-PDD parameters ALREADY calibrated for the ledger
     (results/.../gr4j_pdd_cma_FINAL_pt_v1/<basin>.csv). Those were calibrated
     on the calibration window 1999-10-01..2008-09-30, which IS the contest TRAIN
     window, with maurer forcing -> legal to reuse, NO re-calibration needed.
  2. Forward-run the conceptual model (Numba) from a warmup-year init over BOTH
     the train window and the eval window, reading ONLY forcings + the frozen
     params, recording its internal storages S (production), R (routing), SWE
     (snow) and simulated discharge qsim_concept. The eval-window state
     trajectories are saved to model/concept_states.parquet for predict.py
     (they are an OBSERVATION-FREE function of allowed eval forcings + train-
     calibrated params -> no leakage).
  3. Build the 002_b base feature block (forcing memory/snow/PET + statics) from
     the raw maurer forcings, attach the conceptual state columns by date, pool
     all 531 basins, and fit ONE global XGBoost. Two targets are compared on an
     internal cal/val split of the TRAIN period -- direct log1p(Q) vs residual
     log1p(Q_obs)-log1p(qsim_concept) -- and the winner is refit on the full
     train window.

Saves model/xgb.json + model/features.json + model/concept_states.parquet.
Run via the spine:
    python -m fair_benchmark.run_candidate --exp src/fair_benchmark/experiments/002_hybrid_concept_state_gbm
"""
import json
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
import xgboost as xgb

_EXP = Path(__file__).resolve().parent
sys.path.insert(0, str(_EXP / "submission"))
import features as F  # noqa: E402  (shared, leakage-clean feature spec)

_REPO = _EXP.parents[3]
sys.path.insert(0, str(_REPO / "src"))

_DATA = _REPO / "data" / "camels_us"
_FROZEN = _EXP.parents[1] / "frozen"  # .../src/fair_benchmark/frozen
_BASINS_FILE = _FROZEN / "track0_forcing_only_basins.txt"
_STATICS = _FROZEN / "bundle" / "track0_statics.csv"
_MODEL_DIR = _EXP / "model"
_GR4J_FINAL = (_REPO / "results/10_global_conceptual_model_benchmark"
               / "camels_us_531_repro_v01" / "gr4j_pdd_cma_FINAL_pt_v1")

# Contest windows (reverse split, Kratzert 2019).
TRAIN_START, TRAIN_END = "1999-10-01", "2008-09-30"
EVAL_START, EVAL_END = "1989-10-01", "1999-09-30"
WARMUP_START = "1998-10-01"          # 1-yr warmup for the base rolling features
INTERNAL_VAL_START = "2006-10-01"    # cal < this <= val, both inside TRAIN

# GR4J-PDD parameter names (snow-first joint vector), as stored in the FINAL csv.
PDD_GR4J_PARAM_NAMES = [
    "pdd_factor_snow", "refreeze_snow", "temp_snow", "temp_rain",
    "x1", "x2", "x3", "x4",
]

XGB_PARAMS = {
    "objective": "reg:squarederror",
    "eval_metric": "rmse",
    "tree_method": "hist",
    "learning_rate": 0.04,
    "max_depth": 9,
    "min_child_weight": 40.0,
    "subsample": 0.8,
    "colsample_bytree": 0.8,
    "reg_lambda": 1.0,
    "max_bin": 255,
    "nthread": 0,
    "seed": 0,
}
NUM_ROUNDS = 700


# --------------------------------------------------------------------------- #
# Conceptual-model trajectory simulator (Numba; mirrors gr4j_numba exactly,    #
# additionally recording S / R / snow per timestep).                           #
# --------------------------------------------------------------------------- #
try:
    from numba import njit
    _HAS_NUMBA = True
except Exception:  # pragma: no cover
    _HAS_NUMBA = False

    def njit(*a, **k):
        def wrap(f):
            return f
        return wrap

_NUH1_MAX = 20
_NUH2_MAX = 40


@njit(cache=True, fastmath=True)
def _sim_traj(rain, pet, temp, fsnow, rfsnow, temp_snow, temp_rain, x1, x2, x3, x4):
    T = rain.size
    nuh1 = int(np.ceil(x4))
    if nuh1 < 1:
        nuh1 = 1
    nuh2 = int(np.ceil(2.0 * x4))
    if nuh2 < 1:
        nuh2 = 1

    uh1 = np.zeros(_NUH1_MAX)
    prev = 0.0
    for j in range(1, nuh1 + 1):
        tj = j / x4
        sh = tj ** 2.5 if tj < 1.0 else 1.0
        uh1[j - 1] = sh - prev
        prev = sh
    uh2 = np.zeros(_NUH2_MAX)
    prev = 0.0
    for j in range(1, nuh2 + 1):
        tj = j / x4
        if tj <= 1.0:
            sh = 0.5 * tj ** 2.5
        elif tj < 2.0:
            sh = 1.0 - 0.5 * (2.0 - tj) ** 2.5
        else:
            sh = 1.0
        uh2[j - 1] = sh - prev
        prev = sh

    snow_depth = 0.0
    S = 0.5 * x1
    R = 0.5 * x3
    stuh1 = np.zeros(_NUH1_MAX)
    stuh2 = np.zeros(_NUH2_MAX)

    q = np.zeros(T)
    S_tr = np.zeros(T)
    R_tr = np.zeros(T)
    snow_tr = np.zeros(T)

    for t in range(T):
        tv = temp[t]
        snow_frac = (temp_rain - tv) / (temp_rain - temp_snow + 1e-12)
        if snow_frac < 0.0:
            snow_frac = 0.0
        elif snow_frac > 1.0:
            snow_frac = 1.0
        snowfall = rain[t] * snow_frac
        rainfall = rain[t] - snowfall
        snow_depth += snowfall
        pdd = tv if tv > 0.0 else 0.0
        pot_melt = fsnow * pdd
        act_melt = snow_depth if snow_depth < pot_melt else pot_melt
        refrozen = act_melt * rfsnow
        snow_depth = snow_depth - act_melt + refrozen
        if snow_depth < 0.0:
            snow_depth = 0.0
        P = act_melt - refrozen + rainfall
        E = pet[t]

        if P >= E:
            Pn = P - E
            sr = S / x1
            tws = np.tanh(Pn / x1)
            Ps = x1 * (1.0 - sr * sr) * tws / (1.0 + sr * tws)
            S = S + Ps
            pr_excess = Pn - Ps
        else:
            En = E - P
            sr = S / x1
            tws = np.tanh(En / x1)
            Es = S * (2.0 - sr) * tws / (1.0 + (1.0 - sr) * tws)
            S = S - Es
            pr_excess = 0.0

        perc = S * (1.0 - (1.0 + (S / (2.25 * x1)) ** 4) ** (-0.25))
        S = S - perc
        Pr = perc + pr_excess
        prr = 0.9 * Pr
        prd = 0.1 * Pr

        for k in range(nuh1):
            stuh1[k] += uh1[k] * prr
        q9 = stuh1[0]
        for k in range(nuh1 - 1):
            stuh1[k] = stuh1[k + 1]
        stuh1[nuh1 - 1] = 0.0

        for k in range(nuh2):
            stuh2[k] += uh2[k] * prd
        q1 = stuh2[0]
        for k in range(nuh2 - 1):
            stuh2[k] = stuh2[k + 1]
        stuh2[nuh2 - 1] = 0.0

        Fx = x2 * (R / x3) ** 3.5
        R = R + q9 + Fx
        if R < 0.0:
            R = 0.0
        qr = R * (1.0 - (1.0 + (R / x3) ** 4) ** (-0.25))
        R = R - qr
        qd = q1 + Fx
        if qd < 0.0:
            qd = 0.0
        qt = qr + qd

        q[t] = qt if qt > 0.0 else 0.0
        S_tr[t] = S
        R_tr[t] = R
        snow_tr[t] = snow_depth

    return q, S_tr, R_tr, snow_tr


def _load_params(basin):
    row = pd.read_csv(_GR4J_FINAL / f"{basin}.csv", keep_default_na=False).iloc[0]
    if row.get("run_status") != "success":
        return None
    return {p: float(row[f"p_{p}"]) for p in PDD_GR4J_PARAM_NAMES}


def _concept_states_for_window(basin, params, win_start, win_end):
    """Forward-run GR4J-PDD over [win_start-1yr .. win_end]; return per-date states
    on [win_start .. win_end]. Reads forcings only (priestley_taylor PET)."""
    from hydroagent.data_loading import load_camels_basin
    w_start = (pd.Timestamp(win_start) - pd.DateOffset(years=1)).strftime("%Y-%m-%d")
    fw, _, _ = load_camels_basin(basin, data_root=str(_DATA), start_date=w_start,
                                 end_date=win_end, forcing="maurer",
                                 pet_method="priestley_taylor", keep_obs_nan_days=True)
    rain = np.nan_to_num(fw["prcp"].to_numpy(dtype=np.float64))
    pet = np.nan_to_num(fw["ep"].to_numpy(dtype=np.float64))
    temp = np.nan_to_num(fw["tmean"].to_numpy(dtype=np.float64))
    q, S, R, snow = _sim_traj(rain, pet, temp,
                              params["pdd_factor_snow"], params["refreeze_snow"],
                              params["temp_snow"], params["temp_rain"],
                              params["x1"], params["x2"], params["x3"], params["x4"])
    df = pd.DataFrame({
        "date": pd.to_datetime(fw.index),
        "concept_S": S, "concept_R": R, "concept_swe": snow,
        "concept_qsim": q, "concept_qsim_log": np.log1p(np.clip(q, 0.0, None)),
    })
    m = (df["date"] >= pd.Timestamp(win_start)) & (df["date"] <= pd.Timestamp(win_end))
    return df[m].reset_index(drop=True)


def _load_basin_training_frame(basin, statics, params, feat_cols):
    """Per-basin training rows: base features + concept states + obs target."""
    from neuralhydrology.datasetzoo.camelsus import (load_camels_us_discharge,
                                                     load_camels_us_forcings)
    forc, area = load_camels_us_forcings(_DATA, basin, "maurer")
    forc = forc.loc[WARMUP_START:TRAIN_END, F.DYN_COLS].copy()
    if forc.empty:
        return None
    forc.insert(0, "date", forc.index)
    forc = forc.reset_index(drop=True)

    base = F.build_forcing_frame(forc, statics.loc[basin])
    concept = _concept_states_for_window(basin, params, TRAIN_START, TRAIN_END)
    frame = F.attach_concept_states(base, concept)

    q = load_camels_us_discharge(_DATA, basin, area)  # mm/day
    q = q.loc[WARMUP_START:TRAIN_END]
    q = q.where(q >= 0.0)  # CAMELS missing flag -> negative -> NaN
    frame["q"] = q.reindex(frame["date"]).to_numpy()

    frame = frame[frame["date"] >= pd.Timestamp(TRAIN_START)]
    frame = frame.dropna(subset=["q"])
    frame = frame.dropna(subset=["concept_qsim"])  # need concept for both targets
    if frame.empty:
        return None
    return frame[["date"] + feat_cols + ["q"]]  # concept_qsim already in feat_cols


def _nse_np(obs, sim):
    mask = np.isfinite(obs) & np.isfinite(sim)
    if mask.sum() < 2:
        return np.nan
    o = obs[mask]
    s = sim[mask]
    denom = float(((o - o.mean()) ** 2).sum())
    if denom == 0.0:
        return np.nan
    return 1.0 - float(((s - o) ** 2).sum()) / denom


def _median_val_nse(pred_q, obs_q, basin_ids_val):
    """Median per-basin NSE; all three arrays already restricted to val rows."""
    scores = []
    for b in np.unique(basin_ids_val):
        sel = basin_ids_val == b
        scores.append(_nse_np(obs_q[sel], pred_q[sel]))
    return float(np.nanmedian(np.array(scores, dtype=float)))


def _fit(X, y, rounds=NUM_ROUNDS, feat_cols=None):
    dtrain = xgb.DMatrix(X, label=y, feature_names=feat_cols)
    return xgb.train(XGB_PARAMS, dtrain, num_boost_round=rounds)


def main():
    t0 = time.time()
    basins = [b.strip().zfill(8) for b in _BASINS_FILE.read_text().splitlines() if b.strip()]
    statics = F.load_statics(_STATICS)
    feat_cols = F.feature_columns()
    print(f"[train] {len(basins)} basins, {len(feat_cols)} features", flush=True)

    frames, eval_state_frames, n_ok = [], [], 0
    for i, b in enumerate(basins):
        params = _load_params(b)
        if params is None:
            print(f"[train]   WARN basin {b}: no calibrated params", flush=True)
            continue
        try:
            tf = _load_basin_training_frame(b, statics, params, feat_cols)
        except Exception as e:  # pragma: no cover
            print(f"[train]   WARN basin {b}: train frame failed ({e})", flush=True)
            tf = None
        if tf is None:
            continue
        tf = tf.copy()
        tf["basin"] = b
        frames.append(tf)

        # eval-window concept states for predict.py
        ev = _concept_states_for_window(b, params, EVAL_START, EVAL_END)
        ev.insert(0, "basin", b)
        eval_state_frames.append(ev)
        n_ok += 1
        if (i + 1) % 100 == 0:
            print(f"[train]   processed {i + 1}/{len(basins)} basins "
                  f"({time.time() - t0:.0f}s)", flush=True)

    pooled = pd.concat(frames, ignore_index=True)
    X = pooled[feat_cols].to_numpy(dtype=np.float32)
    q_obs = pooled["q"].to_numpy(dtype=np.float64)
    q_concept = pooled["concept_qsim"].to_numpy(dtype=np.float64)
    basin_ids = pooled["basin"].to_numpy()
    dates = pooled["date"].to_numpy()
    print(f"[train] pooled matrix: {X.shape[0]:,} rows x {X.shape[1]} features "
          f"from {n_ok} basins ({time.time() - t0:.0f}s)", flush=True)

    y_direct = np.log1p(q_obs)
    y_resid = np.log1p(q_obs) - np.log1p(np.clip(q_concept, 0.0, None))

    # --- internal cal/val target-mode selection (all inside TRAIN window) ---
    val_mask = dates >= np.datetime64(INTERNAL_VAL_START)
    cal_mask = ~val_mask
    results = {}
    for mode, y in (("direct", y_direct), ("residual", y_resid)):
        bst = _fit(X[cal_mask], y[cal_mask], feat_cols=feat_cols)
        dval = xgb.DMatrix(X[val_mask], feature_names=feat_cols)
        pred = bst.predict(dval)
        if mode == "direct":
            pred_q = np.expm1(pred)
        else:
            pred_q = np.expm1(pred + np.log1p(np.clip(q_concept[val_mask], 0.0, None)))
        pred_q = np.clip(pred_q, 0.0, None)
        med = _median_val_nse(pred_q, q_obs[val_mask], basin_ids[val_mask])
        results[mode] = med
        print(f"[train]   internal-val median NSE [{mode}] = {med:.4f}", flush=True)

    target_mode = "direct" if results["direct"] >= results["residual"] else "residual"
    print(f"[train] selected target_mode = {target_mode} "
          f"(direct {results['direct']:.4f} vs residual {results['residual']:.4f})", flush=True)

    # --- refit on the FULL train window with the winning target ---
    y_full = y_direct if target_mode == "direct" else y_resid
    booster = _fit(X, y_full, feat_cols=feat_cols)

    _MODEL_DIR.mkdir(parents=True, exist_ok=True)
    booster.save_model(str(_MODEL_DIR / "xgb.json"))

    eval_states = pd.concat(eval_state_frames, ignore_index=True)
    eval_states["date"] = pd.to_datetime(eval_states["date"]).dt.strftime("%Y-%m-%d")
    eval_states.to_parquet(_MODEL_DIR / "concept_states.parquet", index=False)

    spec = {
        "feature_columns": feat_cols,
        "target_mode": target_mode,
        "target": ("log1p(Q_mm_per_day)" if target_mode == "direct"
                   else "log1p(Q_obs) - log1p(qsim_concept)"),
        "concept_state_cols": F.CONCEPT_STATE_COLS,
        "dyn_cols": F.DYN_COLS,
        "static_cols": F.STATIC_COLS,
        "xgb_params": XGB_PARAMS,
        "num_rounds": NUM_ROUNDS,
        "train_window": [TRAIN_START, TRAIN_END],
        "eval_window": [EVAL_START, EVAL_END],
        "warmup_start": WARMUP_START,
        "internal_val_start": INTERNAL_VAL_START,
        "internal_val_median_nse": results,
        "n_train_rows": int(X.shape[0]),
        "n_basins": int(n_ok),
        "gr4j_params_source": str(_GR4J_FINAL.relative_to(_REPO)),
    }
    (_MODEL_DIR / "features.json").write_text(json.dumps(spec, indent=2), encoding="utf-8")
    print(f"[train] saved model + features.json + concept_states.parquet -> {_MODEL_DIR} "
          f"({time.time() - t0:.0f}s total)", flush=True)


if __name__ == "__main__":
    main()
