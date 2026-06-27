"""000_ref reference submission — smoke-tests the run_candidate spine.

Reads ONLY the allowed bundle; emits qsim = 0.3*PRCP over the eval window for all
531 basins. Intentionally bad (will HOLD), here only to prove the execute->score
loop closes. NOTE the bundle path: a submission lives at
experiments/<exp>/submission/predict.py, so the bundle is parents[3]/frozen/bundle.
"""
import argparse
from pathlib import Path

import pandas as pd

_BUNDLE = Path(__file__).resolve().parents[3] / "frozen" / "bundle"
_EVAL_START, _EVAL_END = "1989-10-01", "1999-09-30"


def predict(out_csv):
    f = pd.read_parquet(_BUNDLE / "track0_forcing.parquet")
    f["basin"] = f["basin"].astype(str)
    f["date"] = pd.to_datetime(f["date"])
    m = (f["date"] >= _EVAL_START) & (f["date"] <= _EVAL_END)
    d = f.loc[m].copy()
    d["qsim"] = (0.3 * d["PRCP(mm/day)"]).clip(lower=0.0)
    out = d[["basin", "date", "qsim"]].copy()
    out["date"] = out["date"].dt.strftime("%Y-%m-%d")
    Path(out_csv).parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(out_csv, index=False)
    print(f"wrote {len(out)} rows / {out['basin'].nunique()} basins -> {out_csv}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="predictions.csv")
    predict(p.parse_args().out)
