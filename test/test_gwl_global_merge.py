import numpy as np
import pandas as pd
import pytest

from src.gwl_global.merge import merge_single_well, interpolate_short_gaps


def test_interpolate_short_gaps():
    s = pd.Series(
        [1.0, np.nan, np.nan, 4.0, np.nan, np.nan, np.nan, np.nan, np.nan, np.nan, 10.0]
    )
    result = interpolate_short_gaps(s, max_gap=5)
    # 2-day gap filled, 6-day gap NOT filled
    assert not np.isnan(result.iloc[1])
    assert not np.isnan(result.iloc[2])
    assert np.isnan(result.iloc[4])


def test_merge_single_well(tmp_path):
    # Create fake GWL
    dates_gwl = pd.date_range("2020-01-01", "2020-12-31", freq="D")
    gwl = pd.DataFrame(
        {"gwl_m_nap": np.sin(np.arange(len(dates_gwl)) * 0.01) - 2.0},
        index=dates_gwl,
    )
    gwl_path = tmp_path / "timeseries" / "TEST001_gwl.csv"
    gwl_path.parent.mkdir(parents=True)
    gwl.to_csv(gwl_path, index_label="date")

    # Create fake KNMI
    dates_knmi = pd.date_range("2020-01-01", "2020-12-31", freq="D")
    knmi = pd.DataFrame(
        {
            "P_mm": np.random.rand(len(dates_knmi)) * 5,
            "ET_mm": np.random.rand(len(dates_knmi)) * 3,
        },
        index=dates_knmi,
    )
    knmi_path = tmp_path / "meteo" / "knmi_260_daily.csv"
    knmi_path.parent.mkdir(parents=True)
    knmi.to_csv(knmi_path, index_label="date")

    result = merge_single_well("TEST001", 260, tmp_path)
    assert result is not None
    assert "gwl_m_nap" in result.columns
    assert "P_mm" in result.columns
    assert "ET_mm" in result.columns
    assert len(result) == 366  # 2020 is leap year


def test_merge_saves_csv(tmp_path):
    dates = pd.date_range("2020-01-01", "2021-06-30", freq="D")
    gwl = pd.DataFrame({"gwl_m_nap": np.ones(len(dates)) * -1.5}, index=dates)
    gwl_path = tmp_path / "timeseries" / "W001_gwl.csv"
    gwl_path.parent.mkdir(parents=True)
    gwl.to_csv(gwl_path, index_label="date")

    knmi = pd.DataFrame(
        {"P_mm": np.ones(len(dates)) * 2.0, "ET_mm": np.ones(len(dates)) * 1.0},
        index=dates,
    )
    knmi_path = tmp_path / "meteo" / "knmi_260_daily.csv"
    knmi_path.parent.mkdir(parents=True)
    knmi.to_csv(knmi_path, index_label="date")

    result = merge_single_well("W001", 260, tmp_path, save=True)
    merged_path = tmp_path / "merged" / "W001_merged.csv"
    assert merged_path.exists()
