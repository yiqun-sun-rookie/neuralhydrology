from pathlib import Path
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from data import (
    DataPack,
    compute_scaler,
    default_periods,
    model_input_arrays,
    split_target_indices,
)
from select_basins import farthest_point_basin_selection


def _dates():
    periods = default_periods()
    return pd.date_range(periods.history_start, periods.validation_end, freq="D")


def test_target_indices_respect_history_and_frozen_split_dates():
    dates = _dates()
    target = np.ones((2, len(dates)), dtype=np.float32)

    train = split_target_indices(dates, target, split="train")
    validation = split_target_indices(dates, target, split="validation")

    assert dates[train[1].min()] == pd.Timestamp("1999-10-01")
    assert dates[train[1].max()] == pd.Timestamp("2006-09-30")
    assert dates[validation[1].min()] == pd.Timestamp("2006-10-01")
    assert dates[validation[1].max()] == pd.Timestamp("2008-09-30")
    assert train[1].min() >= 3649
    assert validation[1].min() >= 3649


def test_scaler_uses_training_target_dates_only():
    dates = _dates()
    periods = default_periods()
    forcing = np.full((2, len(dates), 2), 50.0, dtype=np.float32)
    discharge = np.full((2, len(dates)), 60.0, dtype=np.float32)
    train_mask = np.asarray(
        (dates >= periods.train_start) & (dates <= periods.train_end)
    )
    forcing[:, train_mask] = 1.0
    discharge[:, train_mask] = 2.0
    statics = np.asarray([[0.0, 2.0], [2.0, 4.0]], dtype=np.float32)

    scaler = compute_scaler(forcing, discharge, statics, dates)

    np.testing.assert_allclose(scaler["dynamic_center"], [1.0, 1.0])
    assert scaler["q_center"] == 2.0
    np.testing.assert_allclose(scaler["static_center"], [1.0, 3.0])


def test_model_inputs_exclude_discharge_targets():
    dates = _dates()
    pack = DataPack(
        basins=("00000001",),
        dates=dates,
        forcing=np.zeros((1, len(dates), 5), dtype=np.float32),
        discharge=np.ones((1, len(dates)), dtype=np.float32),
        statics=np.zeros((1, 27), dtype=np.float32),
    )

    model_inputs = model_input_arrays(pack)

    assert set(model_inputs) == {"forcing", "statics"}
    assert all("q" not in key.lower() for key in model_inputs)
    assert all("discharge" not in key.lower() for key in model_inputs)


def test_farthest_point_selection_is_deterministic_and_unique():
    frame = pd.DataFrame(
        {
            "gauge_id": [f"{index:08d}" for index in range(1, 9)],
            "a": [0.0, 0.1, 0.2, 4.0, 4.1, 8.0, 8.1, 12.0],
            "b": [0.0, 0.2, 0.1, 4.1, 4.0, 8.1, 8.0, 12.0],
        }
    )

    first = farthest_point_basin_selection(frame, count=5, feature_columns=["a", "b"])
    second = farthest_point_basin_selection(frame, count=5, feature_columns=["a", "b"])

    assert first == second
    assert len(first) == len(set(first)) == 5
    assert set(first).issubset(set(frame["gauge_id"]))


def test_missing_discharge_days_are_not_training_samples():
    dates = _dates()
    target = np.ones((1, len(dates)), dtype=np.float32)
    missing_date = pd.Timestamp("2001-03-07")
    target[0, dates.get_loc(missing_date)] = np.nan

    basins, times = split_target_indices(dates, target, split="train")

    selected = set(zip(basins.tolist(), times.tolist()))
    assert (0, dates.get_loc(missing_date)) not in selected
