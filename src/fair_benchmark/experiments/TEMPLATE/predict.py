"""TEMPLATE challenger — a runnable TOY that respects the Track-0 contract.

It reads ONLY the allowed bundle (5 Maurer forcings + 27 statics; no observed
discharge) and emits a per-basin daily hydrograph as `predictions.csv`
(basin,date,qsim in mm/day) over the eval window. The "model" is a rational-method
placeholder: qsim = RUNOFF_COEF * PRCP. It exists to prove the pipeline runs and
to be deleted — replace it with any ML/AI method you like, keeping the same
read-only-allowed-inputs / emit-a-hydrograph contract.

Run from repo root:
    python src/fair_benchmark/experiments/TEMPLATE/predict.py --out predictions.csv [--n 5]
"""
import argparse
from pathlib import Path

import pandas as pd

# Allowed bundle (forcing + statics). NEVER read the held answer key or obs.
_BUNDLE = Path(__file__).resolve().parents[2] / "frozen" / "bundle"
_EVAL_START = "1989-10-01"   # eval window per track0_forcing_only.spec.yaml (eval: ...)
_EVAL_END = "1999-09-30"
RUNOFF_COEF = 0.3            # toy: fraction of precipitation that becomes streamflow


def predict(out_csv: str, n: int | None = None) -> None:
    forcing = pd.read_parquet(_BUNDLE / "track0_forcing.parquet")
    forcing["basin"] = forcing["basin"].astype(str)
    forcing["date"] = pd.to_datetime(forcing["date"])
    # statics are available too — a real model would use them; the toy ignores them
    _statics = pd.read_csv(_BUNDLE / "track0_statics.csv", index_col=0)

    eval_mask = (forcing["date"] >= _EVAL_START) & (forcing["date"] <= _EVAL_END)
    df = forcing.loc[eval_mask].copy()
    if n is not None:
        keep = sorted(df["basin"].unique())[:n]
        df = df[df["basin"].isin(keep)]

    df["qsim"] = (RUNOFF_COEF * df["PRCP(mm/day)"]).clip(lower=0.0)
    out = df[["basin", "date", "qsim"]].copy()
    out["date"] = out["date"].dt.strftime("%Y-%m-%d")

    dest = Path(out_csv)
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(dest, index=False)
    print(f"wrote {len(out)} rows for {out['basin'].nunique()} basins -> {dest}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="predictions.csv")
    p.add_argument("--n", type=int, default=None, help="limit to first N basins (smoke test)")
    a = p.parse_args()
    predict(a.out, a.n)
