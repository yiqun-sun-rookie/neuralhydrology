"""Train the 003 Echo-State reservoir + GBM readout for Track-0.

Approach class: reservoir computing / hybrid. A single GLOBAL FROZEN Echo-State
reservoir (random recurrent network, leaky-integrator, mixed per-unit leak rates
for multi-timescale catchment memory) is run over the Maurer forcings to produce
a recurrent-memory STATE trajectory per basin. A single global LightGBM is the
readout on [reservoir states + current inputs + 27 statics] -> log1p(Q). The
reservoir is never trained (echo-state principle): only the cheap tree readout
is fit, so the whole thing is CPU-fast. The recurrent state is what the engineered
rolling features of the 001 baseline only crudely approximate; the hypothesis is
that genuine recurrent memory narrows the gap to the LSTM.

Pipeline (train side -- allowed to read TRAIN-period observed discharge):
  1. Generate the frozen reservoir weights once (seeded) -> model/reservoir.npz.
  2. Compute input-channel standardization stats over the train forcings (an
     observation-free function of allowed forcings) -> saved in features.json.
  3. For each of 531 basins, build the reservoir input over a warmup-year +
     train window, normalize, run the reservoir, attach statics, and keep the
     train-window rows that have a valid observed Q (mm/day). Pool all basins.
  4. Fit ONE global LightGBM on log1p(Q).

Saves model/lgbm.txt + model/reservoir.npz + model/features.json. Run via spine:
    python -m fair_benchmark.run_candidate --exp src/fair_benchmark/experiments/003_reservoir_esn_gbm
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
import features as F  # noqa: E402  (shared, leakage-clean feature + reservoir spec)

_REPO = _EXP.parents[3]
sys.path.insert(0, str(_REPO / "src"))
_DATA = _REPO / "data" / "camels_us"
_FROZEN = _EXP.parents[1] / "frozen"  # .../src/fair_benchmark/frozen
_BASINS_FILE = _FROZEN / "track0_forcing_only_basins.txt"
_STATICS = _FROZEN / "bundle" / "track0_statics.csv"
_MODEL_DIR = _EXP / "model"

# Train period (reverse split, Kratzert 2019) + a one-year warmup so the
# reservoir's zero-init transient decays before the first training target.
WARMUP_START = "1998-10-01"
TRAIN_START = "1999-10-01"
TRAIN_END = "2008-09-30"

RESERVOIR_PARAMS = dict(F.RESERVOIR_DEFAULTS)  # n_units=160, sr=0.9, mixed leaks

LGB_PARAMS = {
    "objective": "regression",
    "metric": "l2",
    "learning_rate": 0.04,
    "num_leaves": 127,
    "min_data_in_leaf": 200,
    "feature_fraction": 0.6,
    "bagging_fraction": 0.8,
    "bagging_freq": 1,
    "max_bin": 255,
    "num_threads": 0,
    "verbosity": -1,
    "seed": 0,
}
NUM_ROUNDS = 700


def _load_basin_forcing(basin):
    """Raw maurer forcing for one basin over warmup+train, or None."""
    from neuralhydrology.datasetzoo.camelsus import load_camels_us_forcings
    forc, area = load_camels_us_forcings(_DATA, basin, "maurer")
    forc = forc.loc[WARMUP_START:TRAIN_END, F.DYN_COLS].copy()
    if forc.empty:
        return None, None
    forc.insert(0, "date", forc.index)
    forc = forc.reset_index(drop=True)
    return forc, area


def _load_basin_discharge(basin, area):
    from neuralhydrology.datasetzoo.camelsus import load_camels_us_discharge
    q = load_camels_us_discharge(_DATA, basin, area)  # mm/day
    q = q.loc[WARMUP_START:TRAIN_END]
    q = q.where(q >= 0.0)  # CAMELS missing flag -> negative -> NaN
    return q


def _compute_input_stats(basins):
    """Mean/std of the leading reservoir input channels over train forcings."""
    sums = np.zeros(len(F.INPUT_COLS))
    sqs = np.zeros(len(F.INPUT_COLS))
    cnt = 0
    forc_cache = {}
    for b in basins:
        forc, area = _load_basin_forcing(b)
        if forc is None:
            continue
        forc_cache[b] = (forc, area)
        _, U, _ = F.build_input_matrix(forc)
        sums += U.sum(axis=0)
        sqs += (U ** 2).sum(axis=0)
        cnt += U.shape[0]
    mean = sums / max(cnt, 1)
    var = np.maximum(sqs / max(cnt, 1) - mean ** 2, 0.0)
    std = np.sqrt(var)
    return mean, std, forc_cache


def _basin_training_rows(basin, forc, area, statics, res, mean, std, feat_cols):
    frame = F.build_basin_frame(forc, statics.loc[basin], res, mean, std)
    q = _load_basin_discharge(basin, area)
    frame["q"] = q.reindex(pd.to_datetime(frame["date"])).to_numpy()
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
    n_units = int(RESERVOIR_PARAMS["n_units"])
    feat_cols = F.feature_columns(n_units)
    print(f"[train] {len(basins)} basins, reservoir n_units={n_units}, "
          f"{len(feat_cols)} readout features", flush=True)

    res = F.build_reservoir(len(F.INPUT_COLS), RESERVOIR_PARAMS)
    print(f"[train] frozen reservoir built (sr={RESERVOIR_PARAMS['spectral_radius']}, "
          f"leaks {RESERVOIR_PARAMS['leak_min']}..{RESERVOIR_PARAMS['leak_max']}) "
          f"({time.time() - t0:.0f}s)", flush=True)

    mean, std, forc_cache = _compute_input_stats(basins)
    print(f"[train] input stats over {len(forc_cache)} basins "
          f"({time.time() - t0:.0f}s)", flush=True)

    Xs, ys, n_ok = [], [], 0
    for i, b in enumerate(basins):
        cached = forc_cache.get(b)
        if cached is None:
            print(f"[train]   WARN basin {b}: no forcing", flush=True)
            continue
        forc, area = cached
        res_rows = _basin_training_rows(b, forc, area, statics, res, mean, std, feat_cols)
        if res_rows is None:
            print(f"[train]   WARN basin {b}: no usable training rows", flush=True)
            continue
        Xs.append(res_rows[0])
        ys.append(res_rows[1])
        n_ok += 1
        if (i + 1) % 100 == 0:
            print(f"[train]   reservoir+rows {i + 1}/{len(basins)} basins "
                  f"({time.time() - t0:.0f}s)", flush=True)

    X = np.concatenate(Xs, axis=0)
    y = np.concatenate(ys, axis=0)
    print(f"[train] pooled matrix: {X.shape[0]:,} rows x {X.shape[1]} features "
          f"from {n_ok} basins ({time.time() - t0:.0f}s)", flush=True)

    dtrain = lgb.Dataset(X, label=y, feature_name=feat_cols)
    booster = lgb.train(LGB_PARAMS, dtrain, num_boost_round=NUM_ROUNDS)

    _MODEL_DIR.mkdir(parents=True, exist_ok=True)
    booster.save_model(str(_MODEL_DIR / "lgbm.txt"))
    np.savez(_MODEL_DIR / "reservoir.npz", w_in=res["w_in"], w=res["w"],
             bias=res["bias"], leak=res["leak"],
             params=np.array(res["params"], dtype=object))
    spec = {
        "feature_columns": feat_cols,
        "target": "log1p(Q_mm_per_day)",
        "input_cols": F.INPUT_COLS,
        "input_mean": mean.tolist(),
        "input_std": std.tolist(),
        "static_cols": F.STATIC_COLS,
        "reservoir_params": RESERVOIR_PARAMS,
        "n_units": n_units,
        "lgb_params": LGB_PARAMS,
        "num_rounds": NUM_ROUNDS,
        "train_window": [TRAIN_START, TRAIN_END],
        "warmup_start": WARMUP_START,
        "n_train_rows": int(X.shape[0]),
        "n_basins": int(n_ok),
    }
    (_MODEL_DIR / "features.json").write_text(json.dumps(spec, indent=2), encoding="utf-8")
    print(f"[train] saved lgbm.txt + reservoir.npz + features.json -> {_MODEL_DIR} "
          f"({time.time() - t0:.0f}s total)", flush=True)


if __name__ == "__main__":
    main()
