"""002_b XGBoost challenger — SUBMISSION side (scanned for leakage).

Reads ONLY the allowed bundle (5 Maurer forcings + 27 statics) and the trained
artifacts in ../../model/. For each of the 531 basins it engineers the SAME
enriched features used at train time (shared submission/features.py), runs the
global XGBoost, inverts the log1p target (expm1), clips negatives to 0, and
writes a long CSV (basin,date,qsim in mm/day) over the eval window for all
basins.

NO observed discharge / answer key / signature file is read here.
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import xgboost as xgb

_HERE = Path(__file__).resolve()
sys.path.insert(0, str(_HERE.parent))
import features as F  # noqa: E402

_BUNDLE = _HERE.parents[3] / "frozen" / "bundle"
_MODEL_DIR = _HERE.parents[1] / "model"
_EVAL_START, _EVAL_END = "1989-10-01", "1999-09-30"


def predict(out_csv):
    booster = xgb.Booster()
    booster.load_model(str(_MODEL_DIR / "xgb.json"))
    spec = json.loads((_MODEL_DIR / "features.json").read_text(encoding="utf-8"))
    feat_cols = spec["feature_columns"]

    forcing = pd.read_parquet(_BUNDLE / "track0_forcing.parquet")
    forcing["basin"] = forcing["basin"].astype(str).str.zfill(8)
    forcing["date"] = pd.to_datetime(forcing["date"])
    statics = F.load_statics(_BUNDLE / "track0_statics.csv")

    eval_start = pd.Timestamp(_EVAL_START)
    eval_end = pd.Timestamp(_EVAL_END)

    out_frames = []
    for basin, g in forcing.groupby("basin", sort=True):
        # Build features over the FULL bundle window (incl. warmup year) so the
        # long rolling / recursive windows are valid, then keep only eval rows.
        frame = F.build_basin_frame(g[["date"] + F.DYN_COLS], statics.loc[basin])
        dates = pd.to_datetime(frame["date"])
        mask = (dates >= eval_start) & (dates <= eval_end)
        frame = frame[mask]
        X = frame[feat_cols].to_numpy(dtype=np.float32)
        dmat = xgb.DMatrix(X, feature_names=feat_cols)
        qsim = np.expm1(booster.predict(dmat))
        qsim = np.clip(qsim, 0.0, None)
        out_frames.append(pd.DataFrame({
            "basin": basin,
            "date": dates[mask].dt.strftime("%Y-%m-%d").to_numpy(),
            "qsim": qsim,
        }))

    out = pd.concat(out_frames, ignore_index=True)
    Path(out_csv).parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(out_csv, index=False)
    print(f"wrote {len(out):,} rows / {out['basin'].nunique()} basins -> {out_csv}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="predictions.csv")
    predict(p.parse_args().out)
