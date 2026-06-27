"""Train ONE global LightGBM rainfall-runoff regressor for Track-0 (001).

Train side (allowed to read TRAIN-period observed discharge). Loads the 5 Maurer
forcings + observed discharge (mm/day) for all 531 basins over the train window
(with a one-year warmup so the long rolling features are valid), engineers the
SAME features predict.py will use (via submission/features.py), pools every
basin into one table, and fits a single LightGBM on log1p(Q). Basins are
distinguished only by their 27 static attributes -> a genuinely global model.

Saves model/lgbm.txt + model/features.json (the exact feature spec predict.py
reloads). Run via the spine:
    python -m fair_benchmark.run_candidate --exp src/fair_benchmark/experiments/001_lightgbm_forcing
"""
import json
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
import lightgbm as lgb

_EXP = Path(__file__).resolve().parent
sys.path.insert(0, str(_EXP / "submission"))
import features as F  # noqa: E402  (shared, leakage-clean feature spec)

_REPO = _EXP.parents[3]
_DATA = _REPO / "data" / "camels_us"
_FROZEN = _EXP.parents[1] / "frozen"  # .../src/fair_benchmark/frozen
_BASINS_FILE = _FROZEN / "track0_forcing_only_basins.txt"
_STATICS = _FROZEN / "bundle" / "track0_statics.csv"
_MODEL_DIR = _EXP / "model"

# Train period (reverse split, Kratzert 2019) + a one-year warmup for rolling.
WARMUP_START = "1998-10-01"
TRAIN_START = "1999-10-01"
TRAIN_END = "2008-09-30"

LGB_PARAMS = {
    "objective": "regression",
    "metric": "l2",
    "learning_rate": 0.04,
    "num_leaves": 127,
    "min_data_in_leaf": 200,
    "feature_fraction": 0.8,
    "bagging_fraction": 0.8,
    "bagging_freq": 1,
    "max_bin": 255,
    "num_threads": 0,
    "verbosity": -1,
    "seed": 0,
}
NUM_ROUNDS = 700


def _load_basin_training_frame(basin, statics, feat_cols):
    """Feature rows + log1p(Q) target for one basin over the train window."""
    from neuralhydrology.datasetzoo.camelsus import (load_camels_us_discharge,
                                                     load_camels_us_forcings)
    forc, area = load_camels_us_forcings(_DATA, basin, "maurer")
    forc = forc.loc[WARMUP_START:TRAIN_END, F.DYN_COLS].copy()
    if forc.empty:
        return None
    forc.insert(0, "date", forc.index)
    forc = forc.reset_index(drop=True)  # drop the 'date'-named index (avoid ambiguity)

    q = load_camels_us_discharge(_DATA, basin, area)  # mm/day
    q = q.loc[WARMUP_START:TRAIN_END]
    q = q.where(q >= 0.0)  # CAMELS missing flag -> negative -> NaN

    frame = F.build_basin_frame(forc, statics.loc[basin])
    frame["q"] = q.reindex(pd.to_datetime(frame["date"])).to_numpy()

    # keep only target rows (warmup feeds rolling but is not a training target)
    frame = frame[pd.to_datetime(frame["date"]) >= pd.Timestamp(TRAIN_START)]
    frame = frame.dropna(subset=["q"])
    if frame.empty:
        return None
    X = frame[feat_cols].to_numpy(dtype=np.float32)
    y = np.log1p(frame["q"].to_numpy(dtype=np.float64))
    return X, y


def main():
    t0 = time.time()
    basins = [b.strip().zfill(8) for b in _BASINS_FILE.read_text().splitlines() if b.strip()]
    statics = F.load_statics(_STATICS)
    feat_cols = F.feature_columns()
    print(f"[train] {len(basins)} basins, {len(feat_cols)} features", flush=True)

    Xs, ys, n_ok = [], [], 0
    for i, b in enumerate(basins):
        res = _load_basin_training_frame(b, statics, feat_cols)
        if res is None:
            print(f"[train]   WARN basin {b}: no usable training rows", flush=True)
            continue
        Xs.append(res[0])
        ys.append(res[1])
        n_ok += 1
        if (i + 1) % 100 == 0:
            print(f"[train]   loaded {i + 1}/{len(basins)} basins", flush=True)

    X = np.concatenate(Xs, axis=0)
    y = np.concatenate(ys, axis=0)
    print(f"[train] pooled matrix: {X.shape[0]:,} rows x {X.shape[1]} features "
          f"from {n_ok} basins ({time.time() - t0:.0f}s)", flush=True)

    dtrain = lgb.Dataset(X, label=y, feature_name=feat_cols)
    booster = lgb.train(LGB_PARAMS, dtrain, num_boost_round=NUM_ROUNDS)

    _MODEL_DIR.mkdir(parents=True, exist_ok=True)
    booster.save_model(str(_MODEL_DIR / "lgbm.txt"))
    spec = {
        "feature_columns": feat_cols,
        "target": "log1p(Q_mm_per_day)",
        "dyn_cols": F.DYN_COLS,
        "static_cols": F.STATIC_COLS,
        "prcp_sum_windows": F.PRCP_SUM_WINDOWS,
        "met_windows": F.MET_WINDOWS,
        "lgb_params": LGB_PARAMS,
        "num_rounds": NUM_ROUNDS,
        "train_window": [TRAIN_START, TRAIN_END],
        "warmup_start": WARMUP_START,
        "n_train_rows": int(X.shape[0]),
        "n_basins": int(n_ok),
    }
    (_MODEL_DIR / "features.json").write_text(json.dumps(spec, indent=2), encoding="utf-8")
    print(f"[train] saved model + features.json -> {_MODEL_DIR} "
          f"({time.time() - t0:.0f}s total)", flush=True)


if __name__ == "__main__":
    main()
