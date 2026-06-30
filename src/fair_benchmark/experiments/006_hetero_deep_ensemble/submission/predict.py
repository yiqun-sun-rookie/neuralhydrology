"""006 heterogeneous deep ensemble — SUBMISSION side (scanned for leakage).

Reads ONLY trained-model artifacts produced by ../train.py:

    ../model/lstm_ens_sim.parquet   obs-stripped 8-seed CudaLSTM ensemble sim
    ../model/deep_ens_sim.parquet   ensemble sim of the new decorrelated deep members
    ../model/manifest.json          member counts + blend recipe

and writes a long CSV [basin, date, qsim] over the eval window for all basins.

Blend = equal-weight mean over every individual member: with n_lstm LSTM members
and n_deep deep members the per-day value is
    q = (n_lstm * lstm_ens + n_deep * deep_ens) / (n_lstm + n_deep)
which is exactly the mean of all (n_lstm + n_deep) member hydrographs. A basin
that the deep members do not cover falls back to the LSTM ensemble, so coverage
is always the full baseline basin set. NO observed discharge / answer key is read.
"""
import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

_HERE = Path(__file__).resolve()
_MODEL = _HERE.parents[1] / "model"


def predict(out_csv):
    manifest = json.loads((_MODEL / "manifest.json").read_text(encoding="utf-8"))
    n_lstm = int(manifest.get("n_lstm", 0))
    n_deep = int(manifest.get("n_deep", 0))

    lstm = pd.read_parquet(_MODEL / "lstm_ens_sim.parquet")
    lstm["basin"] = lstm["basin"].astype(str).str.zfill(8)
    lstm = lstm.rename(columns={"qsim": "q_lstm"})

    deep_path = _MODEL / "deep_ens_sim.parquet"
    if deep_path.exists() and n_deep > 0:
        deep = pd.read_parquet(deep_path)
        deep["basin"] = deep["basin"].astype(str).str.zfill(8)
        deep = deep.rename(columns={"qsim": "q_deep"})
        df = lstm.merge(deep, on=["basin", "date"], how="left")
    else:  # no deep members yet -> baseline-equivalent (pure LSTM ens)
        df = lstm.copy()
        df["q_deep"] = np.nan

    # count-weighted mean = equal weight over all individual members; where a deep
    # value is missing, use the LSTM ensemble alone (full-coverage fallback).
    w_lstm, w_deep = float(n_lstm), float(n_deep)
    has_deep = df["q_deep"].notna()
    q_blend = df["q_lstm"].to_numpy(dtype=float).copy()
    both = (w_lstm + w_deep)
    q_blend[has_deep.to_numpy()] = (
        (w_lstm * df.loc[has_deep, "q_lstm"] + w_deep * df.loc[has_deep, "q_deep"]) / both
    ).to_numpy(dtype=float)

    out = pd.DataFrame({
        "basin": df["basin"].to_numpy(),
        "date": pd.to_datetime(df["date"]).dt.strftime("%Y-%m-%d").to_numpy(),
        "qsim": np.clip(q_blend, 0.0, None),
    }).sort_values(["basin", "date"]).reset_index(drop=True)

    Path(out_csv).parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(out_csv, index=False)
    n_blend = int(has_deep.groupby(df["basin"]).any().sum())
    print(f"wrote {len(out):,} rows / {out['basin'].nunique()} basins -> {out_csv} "
          f"(blended basins: {n_blend}; weights lstm={w_lstm:.0f} deep={w_deep:.0f})")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="predictions.csv")
    predict(p.parse_args().out)
