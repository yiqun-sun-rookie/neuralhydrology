"""Authoritative NSE for the fair benchmark.

ONE authoritative NSE for the whole competition. This replicates
neuralhydrology/evaluation/metrics.py::nse exactly (mask NaN on both sides,
then 1 - sum((sim-obs)^2) / sum((obs-mean(obs))^2)) but operates on pandas
Series so the scoring service has no heavy xarray dependency. A test asserts
numerical equivalence to the neuralhydrology implementation when it is
importable. Degenerate cases (<2 valid pairs, zero-variance obs) return NaN
rather than +/-inf so downstream median/Wilcoxon handle them cleanly.
"""
from typing import Mapping

import numpy as np
import pandas as pd

_MIN_VALID = 2


def nse(obs: pd.Series, sim: pd.Series) -> float:
    """Nash-Sutcliffe Efficiency between two index-aligned series."""
    obs, sim = obs.align(sim, join="inner")
    mask = obs.notna() & sim.notna()
    obs = obs[mask].to_numpy(dtype=float)
    sim = sim[mask].to_numpy(dtype=float)

    if obs.size < _MIN_VALID:
        return float("nan")

    denominator = float(((obs - obs.mean()) ** 2).sum())
    if denominator == 0.0:
        return float("nan")

    numerator = float(((sim - obs) ** 2).sum())
    return 1.0 - numerator / denominator


def per_basin_score(obs: Mapping[str, pd.Series], sim: Mapping[str, pd.Series], metric=nse) -> dict:
    """Per-entity score under any metric(obs, sim)->float. Missing sim -> NaN.

    The metric is a parameter so the engine is task-agnostic; the Track supplies
    it (default = the authoritative NSE). Assumes higher-is-better."""
    result = {}
    for basin, obs_series in obs.items():
        sim_series = sim.get(basin)
        if sim_series is None or len(sim_series) == 0:
            result[basin] = float("nan")
        else:
            result[basin] = metric(obs_series, sim_series)
    return result


def per_basin_nse(obs: Mapping[str, pd.Series], sim: Mapping[str, pd.Series]) -> dict:
    """Per-basin NSE keyed by basin id (convenience = per_basin_score with nse)."""
    return per_basin_score(obs, sim, nse)
