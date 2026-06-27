"""002_hybrid concept-state GBM -- SUBMISSION side (scanned for leakage).

Reads ONLY the allowed bundle (5 Maurer forcings + 27 statics) and the trained
artifacts in ../../model/: the global XGBoost booster, the feature spec, and
model/concept_states.parquet -- the per-basin/per-date conceptual-model state
trajectories (production store S, routing store R, snow store SWE, simulated
discharge qsim_concept). Those states were produced by train.py by forward-
running the GR4J-PDD model from forcings ONLY (no observed discharge), with
per-basin parameters calibrated on the TRAIN window; they are a deterministic,
observation-free function of the allowed eval-period forcings, so reading them
here introduces no answer leakage.

For each of the 531 basins it builds the SAME features used at train time
(shared submission/features.py: 002_b base block + the conceptual state block),
runs the global booster, inverts the target (direct log1p, or residual added
back onto log1p(qsim_concept)), clips negatives to 0, and writes a long CSV
(basin,date,qsim in mm/day) over the eval window for all basins.

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
    target_mode = spec.get("target_mode", "direct")

    forcing = pd.read_parquet(_BUNDLE / "track0_forcing.parquet")
    forcing["basin"] = forcing["basin"].astype(str).str.zfill(8)
    forcing["date"] = pd.to_datetime(forcing["date"])
    statics = F.load_statics(_BUNDLE / "track0_statics.csv")

    concept = pd.read_parquet(_MODEL_DIR / "concept_states.parquet")
    concept["basin"] = concept["basin"].astype(str).str.zfill(8)
    concept["date"] = pd.to_datetime(concept["date"])
    concept_by_basin = dict(tuple(concept.groupby("basin", sort=False)))

    eval_start = pd.Timestamp(_EVAL_START)
    eval_end = pd.Timestamp(_EVAL_END)

    out_frames = []
    for basin, g in forcing.groupby("basin", sort=True):
        # Base features over the FULL bundle window (incl. warmup year) so long
        # rolling/recursive terms are valid, then attach concept states + keep eval.
        base = F.build_forcing_frame(g[["date"] + F.DYN_COLS], statics.loc[basin])
        cdf = concept_by_basin.get(basin, pd.DataFrame(columns=["date"] + F.CONCEPT_STATE_COLS))
        frame = F.attach_concept_states(base, cdf)

        dates = pd.to_datetime(frame["date"])
        mask = (dates >= eval_start) & (dates <= eval_end)
        frame = frame[mask]
        X = frame[feat_cols].to_numpy(dtype=np.float32)
        pred = booster.predict(xgb.DMatrix(X, feature_names=feat_cols))

        if target_mode == "residual":
            q_concept = frame["concept_qsim"].to_numpy(dtype=np.float64)
            qsim = np.expm1(pred + np.log1p(np.clip(np.nan_to_num(q_concept), 0.0, None)))
        else:
            qsim = np.expm1(pred)
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
