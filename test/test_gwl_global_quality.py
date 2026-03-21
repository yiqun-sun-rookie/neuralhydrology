import numpy as np
import pandas as pd
import pytest

from src.gwl_global.quality import check_series_quality


def _make_daily_series(n_days: int, gap_range=None, jump_indices=None):
    """Helper: create a synthetic daily GWL series.

    Args:
        gap_range: tuple (start, end) of indices to set NaN
        jump_indices: list of indices to add +2.0m spikes
    """
    dates = pd.date_range("2000-01-01", periods=n_days, freq="D")
    values = np.sin(np.arange(n_days) * 2 * np.pi / 365) * 0.5 - 2.0  # seasonal cycle
    if gap_range:
        values[gap_range[0]:gap_range[1]] = np.nan
    if jump_indices:
        for i in jump_indices:
            values[i] += 2.0  # >1.0m absolute threshold
    return pd.DataFrame({"gwl_m_nap": values}, index=dates)


def test_good_series_passes():
    df = _make_daily_series(365 * 12)
    result = check_series_quality(df)
    assert result["passed"]
    assert result["n_years"] >= 10
    assert result["n_obs"] >= 200


def test_short_series_fails():
    df = _make_daily_series(365 * 5)
    result = check_series_quality(df)
    assert not result["passed"]
    assert "too_short" in result["fail_reasons"]


def test_too_few_obs_fails():
    # Only 100 observations over 12 years (very sparse)
    dates = pd.date_range("2000-01-01", periods=100, freq="45D")
    values = np.random.randn(100)
    df = pd.DataFrame({"gwl_m_nap": values}, index=dates)
    result = check_series_quality(df)
    assert not result["passed"]
    assert "too_few_obs" in result["fail_reasons"]


def test_long_gap_fails():
    # 12 years daily, but 3-year gap in the middle (> 730 days)
    df = _make_daily_series(365 * 12, gap_range=(365 * 4, 365 * 7))
    result = check_series_quality(df)
    assert not result["passed"]
    assert "long_gap" in result["fail_reasons"]


def test_short_gap_passes():
    # 12 years daily, 1-year gap (365 < 730 days)
    df = _make_daily_series(365 * 12, gap_range=(365 * 5, 365 * 6))
    result = check_series_quality(df)
    assert result["passed"]


def test_jumpy_series_fails():
    # Many jumps > 1.0m: every 50 days
    n_days = 365 * 12
    jump_indices = list(range(50, n_days, 50))  # ~87 jumps / 4380 = 2%
    df = _make_daily_series(n_days, jump_indices=jump_indices)
    result = check_series_quality(df)
    assert not result["passed"]
    assert "too_many_jumps" in result["fail_reasons"]


def test_biweekly_series_passes():
    # Biweekly observations over 15 years, no gaps > 2 years
    dates = pd.date_range("2000-01-01", periods=365, freq="15D")
    values = np.sin(np.arange(365) * 2 * np.pi / 24) * 0.5 - 2.0
    df = pd.DataFrame({"gwl_m_nap": values}, index=dates)
    result = check_series_quality(df)
    assert result["passed"]
    assert result["n_obs"] >= 200
