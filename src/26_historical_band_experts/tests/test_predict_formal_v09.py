"""Formal version-09 evaluation-period prediction tests.

The evaluation geometry checked here comes from `configs/formal_v09_protocol.json` and
`configs/formal_v09_clean_pair_scoring_contract.json`, not from anything observed after
training. The most important test is the recent-slice equivalence: the predictor skips the
120-bin history pooling for the two recent-only families, and that shortcut is only legal
because the recent tensor is a pure trailing slice.
"""
from pathlib import Path
import sys

import numpy as np
import pytest
import torch

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

# Transcribed from the protocol and the clean-pair scoring contract, not computed here.
_EVALUATION_START = "1989-10-01"
_EVALUATION_END = "1999-09-30"
_EVALUATION_DAYS = 3652
_FORCING_DAYS = 10501
_START_INDEX = 3561
_ROWS_PER_FILE = 1939212


def _sealed_dates() -> np.ndarray:
    return np.arange(
        np.datetime64("1980-01-01", "D"),
        np.datetime64("2008-10-01", "D"),
        dtype="datetime64[D]",
    )


def test_sealed_date_axis_matches_the_protocol():
    dates = _sealed_dates()
    assert len(dates) == _FORCING_DAYS
    assert dates[0] == np.datetime64("1980-01-01")
    assert dates[-1] == np.datetime64("2008-09-30")


def test_evaluation_start_index_is_3561_and_the_window_exactly_fits():
    from predict_formal_v09 import evaluation_start_index_v09

    dates = _sealed_dates()
    start = evaluation_start_index_v09(dates)
    assert start == _START_INDEX
    # The 3,562-day causal window reaches back to the first sealed forcing day and no further.
    assert start - (3562 - 1) == 0
    assert dates[start] == np.datetime64(_EVALUATION_START)
    assert dates[start + _EVALUATION_DAYS - 1] == np.datetime64(_EVALUATION_END)


def test_evaluation_period_does_not_overlap_the_training_period():
    from predict_formal_v09 import evaluation_start_index_v09

    dates = _sealed_dates()
    start = evaluation_start_index_v09(dates)
    training_start = int(np.searchsorted(dates, np.datetime64("1999-10-01")))
    assert start + _EVALUATION_DAYS == training_start


def test_evaluation_start_index_rejects_a_truncated_history():
    from predict_formal_v09 import FormalPredictionError, evaluation_start_index_v09

    short = _sealed_dates()[100:]
    with pytest.raises(FormalPredictionError):
        evaluation_start_index_v09(short)


def test_evaluation_keys_are_basin_major_with_contract_row_count():
    from predict_formal_v09 import evaluation_keys_v09

    keys = evaluation_keys_v09(531)
    assert keys.shape == (_ROWS_PER_FILE, 2)
    assert keys.dtype.str == "<i4"
    assert keys.flags.c_contiguous
    assert keys[0].tolist() == [0, 0]
    assert keys[_EVALUATION_DAYS - 1].tolist() == [0, _EVALUATION_DAYS - 1]
    assert keys[_EVALUATION_DAYS].tolist() == [1, 0]
    assert keys[-1].tolist() == [530, _EVALUATION_DAYS - 1]


def test_recent_slice_is_identical_to_the_full_band_split():
    """The recent-only shortcut must be bit-for-bit what split_windows_v09 would return."""
    from bands_formal_v09 import split_windows_v09
    from predict_formal_v09 import _recent_from_windows_v09

    torch.manual_seed(0)
    windows = torch.randn(6, 3562, 5, dtype=torch.float32)
    assert torch.equal(_recent_from_windows_v09(windows), split_windows_v09(windows)["recent"])


def test_recent_slice_rejects_wrong_geometry():
    from predict_formal_v09 import FormalPredictionError, _recent_from_windows_v09

    with pytest.raises(FormalPredictionError):
        _recent_from_windows_v09(torch.zeros(2, 100, 5))
    with pytest.raises(FormalPredictionError):
        _recent_from_windows_v09(torch.zeros(257, 3562, 5))


def test_denormalization_inverts_the_frozen_target_normalization():
    from predict_formal_v09 import denormalize_prediction_v09

    scaler = {"target_center_float64": 1.499961962320709, "target_scale_float64": 3.6244367178040595}
    raw = np.array([0.0, 1.25, -3.5, 42.0], dtype=np.float32)
    center = np.float32(scaler["target_center_float64"])
    scale = np.float32(scaler["target_scale_float64"])
    normalized = (raw - center) / scale
    restored = denormalize_prediction_v09(torch.from_numpy(normalized), scaler)
    assert restored.dtype == np.float64
    np.testing.assert_allclose(restored, raw, rtol=1e-6, atol=1e-6)


def test_denormalization_rejects_an_invalid_scale():
    from predict_formal_v09 import FormalPredictionError, denormalize_prediction_v09

    with pytest.raises(FormalPredictionError):
        denormalize_prediction_v09(torch.zeros(3), {"target_center_float64": 0.0, "target_scale_float64": 0.0})


def test_ensemble_is_the_float64_mean_of_the_eight_frozen_seeds():
    from predict_formal_v09 import compose_family_ensemble_v09

    members = {seed: np.full(4, float(seed), dtype=np.float64) for seed in range(100, 801, 100)}
    ensemble = compose_family_ensemble_v09(members)
    assert ensemble.dtype == np.float64
    np.testing.assert_array_equal(ensemble, np.full(4, 450.0))


def test_ensemble_refuses_a_missing_seed():
    from predict_formal_v09 import FormalPredictionError, compose_family_ensemble_v09

    members = {seed: np.zeros(2, dtype=np.float64) for seed in range(100, 701, 100)}
    with pytest.raises(FormalPredictionError):
        compose_family_ensemble_v09(members)


def test_ensemble_refuses_a_float32_member():
    from predict_formal_v09 import FormalPredictionError, compose_family_ensemble_v09

    members = {seed: np.zeros(2, dtype=np.float64) for seed in range(100, 801, 100)}
    members[400] = np.zeros(2, dtype=np.float32)
    with pytest.raises(FormalPredictionError):
        compose_family_ensemble_v09(members)


def test_prediction_csv_is_basin_major_with_the_contract_columns(tmp_path):
    from predict_formal_v09 import write_prediction_csv_v09

    dates = np.arange(np.datetime64("1989-10-01", "D"), np.datetime64("1989-10-04", "D"), dtype="datetime64[D]")
    basins = ("01013500", "01022500")
    values = np.array([1.0, 2.0, 3.0, 10.0, 20.0, 30.0], dtype=np.float64)
    record = write_prediction_csv_v09(tmp_path / "run.csv", basins, dates, values)

    lines = (tmp_path / "run.csv").read_text(encoding="utf-8").splitlines()
    assert lines[0] == "basin,date,qsim"
    assert lines[1] == "01013500,1989-10-01,1"
    assert lines[3] == "01013500,1989-10-03,3"
    assert lines[4] == "01022500,1989-10-01,10"
    assert record["rows"] == 6
    assert len(lines) == 7


def test_prediction_csv_refuses_to_overwrite(tmp_path):
    from predict_formal_v09 import write_prediction_csv_v09

    dates = np.arange(np.datetime64("1989-10-01", "D"), np.datetime64("1989-10-02", "D"), dtype="datetime64[D]")
    path = tmp_path / "run.csv"
    write_prediction_csv_v09(path, ("01013500",), dates, np.array([1.0]))
    with pytest.raises(FileExistsError):
        write_prediction_csv_v09(path, ("01013500",), dates, np.array([1.0]))


def test_prediction_csv_round_trips_float64_exactly(tmp_path):
    from predict_formal_v09 import write_prediction_csv_v09

    dates = np.arange(np.datetime64("1989-10-01", "D"), np.datetime64("1989-10-04", "D"), dtype="datetime64[D]")
    values = np.array([0.1, 1.0 / 3.0, 1e-9], dtype=np.float64)
    write_prediction_csv_v09(tmp_path / "run.csv", ("01013500",), dates, values)
    restored = np.array(
        [float(line.split(",")[2]) for line in
         (tmp_path / "run.csv").read_text(encoding="utf-8").splitlines()[1:]],
        dtype=np.float64,
    )
    np.testing.assert_array_equal(restored, values)


def test_predict_refuses_an_input_object_exposing_targets():
    from types import SimpleNamespace

    from predict_formal_v09 import FormalPredictionError, evaluation_keys_v09, predict_evaluation_period_v09

    inputs = SimpleNamespace(targets=np.zeros(1), basins=("a",), forcing=None, statics=None, scaler={})
    with pytest.raises(FormalPredictionError):
        predict_evaluation_period_v09(
            inputs, torch.nn.Identity(), "classic_lstm_256_clean", evaluation_keys_v09(1), 3561, device="cpu")


def test_predict_refuses_an_unknown_variant():
    from types import SimpleNamespace

    from predict_formal_v09 import FormalPredictionError, evaluation_keys_v09, predict_evaluation_period_v09

    inputs = SimpleNamespace(basins=("a",), forcing=None, statics=None, scaler={})
    with pytest.raises(FormalPredictionError):
        predict_evaluation_period_v09(
            inputs, torch.nn.Identity(), "nested_history_disabled", evaluation_keys_v09(1), 3561, device="cpu")


def test_source_file_list_covers_every_module_the_prediction_depends_on():
    from predict_formal_v09 import _PREDICTION_SOURCE_FILES

    required = {
        "src/26_historical_band_experts/bands_formal_v09.py",
        "src/26_historical_band_experts/formal_training_data_v09.py",
        "src/26_historical_band_experts/models_formal_v09.py",
        "src/26_historical_band_experts/predict_formal_v09.py",
        "src/26_historical_band_experts/configs/formal_v09_protocol.json",
        "src/26_historical_band_experts/configs/formal_v09_run_order.json",
    }
    assert required.issubset(set(_PREDICTION_SOURCE_FILES))
    repo_root = IDEA_ROOT.parents[1]
    for relative in _PREDICTION_SOURCE_FILES:
        assert (repo_root / relative).is_file(), relative
