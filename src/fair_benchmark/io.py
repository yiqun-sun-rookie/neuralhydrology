"""Load challenger predictions / held observations; hash files for provenance.

Submission format (long): a CSV or parquet with columns
    basin (str, leading zeros preserved), date (YYYY-MM-DD), qsim (float)
Observations use the same shape with column `qobs`. Returning per-basin pandas
Series keeps the scoring service free of any modelling framework — any
challenger that can emit a hydrograph can compete.
"""
import hashlib
from pathlib import Path

import pandas as pd


def _load_long(path, value_col: str) -> dict:
    path = Path(path)
    if path.suffix == ".parquet":
        df = pd.read_parquet(path)
        df["basin"] = df["basin"].astype(str)
    else:
        df = pd.read_csv(path, dtype={"basin": str})
    df["date"] = pd.to_datetime(df["date"])
    out = {}
    for basin, g in df.groupby("basin", sort=True):
        out[str(basin)] = pd.Series(g[value_col].to_numpy(dtype=float), index=g["date"].to_numpy())
    return out


def load_predictions(path) -> dict:
    return _load_long(path, "qsim")


def load_obs_csv(path) -> dict:
    return _load_long(path, "qobs")


def sha256_file(path) -> str:
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()
