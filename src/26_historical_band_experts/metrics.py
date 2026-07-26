"""Independent validation metrics for the historical-band pilot."""
from __future__ import annotations

import numpy as np
import pandas as pd


def nash_sutcliffe_efficiency(observed: np.ndarray, simulated: np.ndarray) -> float:
    observed = np.asarray(observed, dtype=np.float64)
    simulated = np.asarray(simulated, dtype=np.float64)
    valid = np.isfinite(observed) & np.isfinite(simulated)
    if int(valid.sum()) < 2:
        return float("nan")
    observed = observed[valid]
    simulated = simulated[valid]
    denominator = float(np.square(observed - observed.mean()).sum())
    if denominator <= 0:
        return float("nan")
    return 1.0 - float(np.square(observed - simulated).sum()) / denominator


def per_basin_nse(predictions: pd.DataFrame) -> pd.DataFrame:
    required = {"basin", "date", "qobs", "qsim"}
    missing = required - set(predictions.columns)
    if missing:
        raise ValueError(f"prediction table is missing columns: {sorted(missing)}")
    rows = []
    for basin, frame in predictions.groupby("basin", sort=True):
        observed = frame["qobs"].to_numpy(dtype=np.float64)
        simulated = frame["qsim"].to_numpy(dtype=np.float64)
        valid = np.isfinite(observed) & np.isfinite(simulated)
        rows.append({
            "basin": str(basin).zfill(8),
            "nse": nash_sutcliffe_efficiency(observed, simulated),
            "n_days": int(valid.sum()),
        })
    return pd.DataFrame(rows, columns=["basin", "nse", "n_days"])
