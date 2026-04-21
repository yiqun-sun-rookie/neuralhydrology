from __future__ import annotations

from pathlib import Path
import sys

import numpy as np
import pandas as pd


SCRIPTS_DIR = Path(__file__).resolve().parents[1] / "src" / "namou_kuwei" / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_tirex_screen  # noqa: E402


def test_build_shifted_feature_frame_creates_lead_shifted_rain_and_histflow():
    index = pd.date_range("2020-01-01 00:00:00", periods=6, freq="h")
    df = pd.DataFrame({
        "p_aka": np.arange(6, dtype=float),
        "p_bandang": np.arange(10, 16, dtype=float),
        "qobs": np.arange(100, 106, dtype=float),
    }, index=index)

    frame = run_tirex_screen.build_shifted_feature_frame(
        df=df,
        rainfall_columns=["p_aka", "p_bandang"],
        lead_hours=2,
        include_histflow=True,
    )

    assert list(frame.columns) == ["p_aka_shift2", "p_bandang_shift2", "qobs_shift2", "qobs"]
    assert pd.isna(frame.loc[index[0], "p_aka_shift2"])
    assert pd.isna(frame.loc[index[1], "qobs_shift2"])
    assert frame.loc[index[2], "p_aka_shift2"] == 0.0
    assert frame.loc[index[4], "p_bandang_shift2"] == 12.0
    assert frame.loc[index[5], "qobs_shift2"] == 103.0
    assert frame.loc[index[5], "qobs"] == 105.0


def test_build_supervised_samples_returns_batch_variate_time_tensor():
    index = pd.date_range("2020-01-01 00:00:00", periods=8, freq="h")
    frame = pd.DataFrame({
        "p_aka_shift1": np.arange(8, dtype=float),
        "qobs_shift1": np.arange(50, 58, dtype=float),
        "qobs": np.arange(100, 108, dtype=float),
    }, index=index)

    x, y, timestamps = run_tirex_screen.build_supervised_samples(
        frame=frame,
        feature_columns=["p_aka_shift1", "qobs_shift1"],
        target_column="qobs",
        seq_length=3,
        start_timestamp=index[2],
        end_timestamp=index[6],
    )

    assert x.shape == (5, 2, 3)
    assert y.shape == (5, 1)
    assert list(timestamps) == list(index[2:7])

    np.testing.assert_allclose(x[0], np.array([[0.0, 1.0, 2.0], [50.0, 51.0, 52.0]], dtype=np.float32))
    np.testing.assert_allclose(y[:, 0], np.array([102.0, 103.0, 104.0, 105.0, 106.0], dtype=np.float32))
