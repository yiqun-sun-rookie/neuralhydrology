from pathlib import Path
import hashlib
import json
import sys

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import data
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

def _write_complete_target_bundle(tmp_path, basins=("00000001", "00000002")):
    periods = default_periods()
    dates = pd.date_range(periods.train_start, periods.validation_end, freq="D")
    rows = []
    for basin_index, basin in enumerate(basins):
        for day_index, date in enumerate(dates):
            rows.append({
                "basin": basin,
                "date": date.strftime("%Y-%m-%d"),
                "qobs": float(basin_index + 1 + day_index / 1000),
            })
    path = tmp_path / "targets.csv"
    pd.DataFrame(rows).to_csv(path, index=False)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return path, digest, dates


def test_target_bundle_accepts_only_complete_frozen_basin_dates(tmp_path):
    path, digest, dates = _write_complete_target_bundle(tmp_path)

    frame = data.load_target_bundle(path, digest, ("00000001", "00000002"))

    assert len(frame) == 2 * len(dates)
    assert frame["date"].min() == pd.Timestamp("1999-10-01")
    assert frame["date"].max() == pd.Timestamp("2008-09-30")


def test_target_bundle_rejects_hash_mismatch(tmp_path):
    path, _digest, _dates = _write_complete_target_bundle(tmp_path)

    with pytest.raises(ValueError, match="SHA-256"):
        data.load_target_bundle(path, "0" * 64, ("00000001", "00000002"))


def test_target_bundle_rejects_duplicate_daily_key(tmp_path):
    path, _digest, _dates = _write_complete_target_bundle(tmp_path)
    frame = pd.read_csv(path)
    pd.concat([frame, frame.iloc[[0]]], ignore_index=True).to_csv(path, index=False)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()

    with pytest.raises(ValueError, match="duplicate"):
        data.load_target_bundle(path, digest, ("00000001", "00000002"))


def test_target_bundle_rejects_out_of_range_date(tmp_path):
    path, _digest, _dates = _write_complete_target_bundle(tmp_path)
    frame = pd.read_csv(path)
    frame.loc[0, "date"] = "1999-09-30"
    frame.to_csv(path, index=False)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()

    with pytest.raises(ValueError, match="date range"):
        data.load_target_bundle(path, digest, ("00000001", "00000002"))


def test_target_bundle_rejects_basin_mismatch(tmp_path):
    path, digest, _dates = _write_complete_target_bundle(tmp_path)

    with pytest.raises(ValueError, match="basin"):
        data.load_target_bundle(path, digest, ("00000001", "00000003"))


def test_trusted_preparation_emits_no_formal_evaluation_rows(tmp_path):
    from prepare_targets import prepare_target_bundle

    periods = default_periods()
    allowed_dates = pd.date_range(periods.train_start, periods.validation_end, freq="D")
    protected_date = pd.Timestamp("1989-10-01")

    def load_one(_basin):
        index = allowed_dates.insert(0, protected_date)
        return pd.Series(np.arange(len(index), dtype=np.float64), index=index)

    basin_file = tmp_path / "basins.txt"
    basin_file.write_text("00000001\n00000002\n", encoding="utf-8")
    output = tmp_path / "targets.csv"
    manifest = prepare_target_bundle(
        basins=("00000001", "00000002"),
        basin_file=basin_file,
        output_path=output,
        load_one=load_one,
    )

    emitted = pd.read_csv(output, dtype={"basin": str})
    assert emitted["date"].min() == "1999-10-01"
    assert emitted["date"].max() == "2008-09-30"
    assert "1989-10-01" not in set(emitted["date"])
    assert manifest["formal_evaluation_rows_emitted"] == 0
    assert manifest["trusted_raw_streamflow_files_read"] == 2
    assert manifest["candidate_raw_streamflow_files_read"] == 0
    assert json.loads(output.with_suffix(".manifest.json").read_text(encoding="utf-8")) == manifest


def test_candidate_loader_source_has_no_raw_discharge_reference():
    source = Path(data.__file__).read_text(encoding="utf-8")

    assert "load_camels_us_discharge" not in source
    assert "usgs_streamflow" not in source

def test_trusted_preparation_refuses_to_overwrite_existing_bundle(tmp_path):
    from prepare_targets import prepare_target_bundle

    basin_file = tmp_path / "basins.txt"
    basin_file.write_text("00000001\n", encoding="utf-8")
    output = tmp_path / "targets.csv"
    output.write_text("preserve", encoding="utf-8")

    with pytest.raises(FileExistsError, match="already exists"):
        prepare_target_bundle(
            basins=("00000001",),
            basin_file=basin_file,
            output_path=output,
            load_one=lambda _basin: pd.Series(dtype=float),
        )

    assert output.read_text(encoding="utf-8") == "preserve"
