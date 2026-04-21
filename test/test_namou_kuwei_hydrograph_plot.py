from __future__ import annotations

from pathlib import Path
import sys

import numpy as np
import pandas as pd
import xarray as xr


SCRIPTS_DIR = Path(__file__).resolve().parents[1] / "src" / "namou_kuwei" / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import plot_typical_hydrograph  # noqa: E402


def test_extract_eval_series_from_dataset_uses_time_step_zero():
    index = pd.date_range("2022-01-01 00:00:00", periods=4, freq="h")
    ds = xr.Dataset(
        data_vars={
            "qobs_obs": (("date", "time_step"), np.array([[1.0], [2.0], [3.0], [4.0]], dtype=np.float32)),
            "qobs_sim": (("date", "time_step"), np.array([[1.1], [1.9], [2.8], [4.2]], dtype=np.float32)),
        },
        coords={"date": index, "time_step": [0]},
    )

    series = plot_typical_hydrograph.extract_eval_series_from_dataset(ds)

    assert list(series.columns) == ["obs", "sim"]
    assert list(series.index) == list(index)
    np.testing.assert_allclose(series["obs"].to_numpy(), np.array([1.0, 2.0, 3.0, 4.0], dtype=np.float32))
    np.testing.assert_allclose(series["sim"].to_numpy(), np.array([1.1, 1.9, 2.8, 4.2], dtype=np.float32))


def test_select_peak_window_returns_symmetric_clipped_slice():
    index = pd.date_range("2022-01-01 00:00:00", periods=10, freq="h")
    obs = pd.Series([1, 2, 4, 7, 12, 6, 3, 2, 1, 1], index=index, dtype=float)

    start, end, peak_time = plot_typical_hydrograph.select_peak_window(obs=obs, hours_before=2, hours_after=3)

    assert peak_time == index[4]
    assert start == index[2]
    assert end == index[7]
