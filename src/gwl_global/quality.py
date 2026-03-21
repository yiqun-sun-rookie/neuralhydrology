"""Quality checks for groundwater level time series."""
import numpy as np
import pandas as pd

from src.gwl_global.config import (
    MIN_SERIES_YEARS,
    MIN_OBS_COUNT,
    MAX_GAP_DAYS,
    MAX_JUMP_FRACTION,
    JUMP_ABS_THRESHOLD_M,
)


def check_series_quality(df: pd.DataFrame) -> dict:
    """Run QC checks on a GWL time series DataFrame.

    Checks:
        1. span >= MIN_SERIES_YEARS
        2. n_obs >= MIN_OBS_COUNT
        3. max consecutive gap <= MAX_GAP_DAYS
        4. jump_fraction (|diff| > JUMP_ABS_THRESHOLD_M) <= MAX_JUMP_FRACTION

    Args:
        df: DataFrame with DatetimeIndex and column 'gwl_m_nap'.

    Returns:
        Dict with keys: passed, n_years, n_obs, max_gap_days,
        jump_fraction, fail_reasons.
    """
    result = {
        "passed": True,
        "n_years": 0.0,
        "n_obs": 0,
        "max_gap_days": 0.0,
        "jump_fraction": 0.0,
        "fail_reasons": [],
    }

    gwl = df["gwl_m_nap"].dropna()
    result["n_obs"] = len(gwl)

    if len(gwl) < 2:
        result["passed"] = False
        result["fail_reasons"].append("too_short")
        return result

    # 1. Span in years
    span_days = (gwl.index[-1] - gwl.index[0]).days
    result["n_years"] = span_days / 365.25

    if result["n_years"] < MIN_SERIES_YEARS:
        result["passed"] = False
        result["fail_reasons"].append("too_short")

    # 2. Minimum observation count
    if result["n_obs"] < MIN_OBS_COUNT:
        result["passed"] = False
        result["fail_reasons"].append("too_few_obs")

    # 3. Maximum consecutive gap
    intervals = pd.Series(gwl.index).diff().dt.days.dropna()
    result["max_gap_days"] = float(intervals.max()) if len(intervals) > 0 else 0.0

    if result["max_gap_days"] > MAX_GAP_DAYS:
        result["passed"] = False
        result["fail_reasons"].append("long_gap")

    # 4. Jump detection: absolute threshold
    diff = gwl.diff().abs().dropna()
    if len(diff) > 10:
        n_jumps = (diff > JUMP_ABS_THRESHOLD_M).sum()
        result["jump_fraction"] = float(n_jumps / len(diff))

        if result["jump_fraction"] > MAX_JUMP_FRACTION:
            result["passed"] = False
            result["fail_reasons"].append("too_many_jumps")

    return result
