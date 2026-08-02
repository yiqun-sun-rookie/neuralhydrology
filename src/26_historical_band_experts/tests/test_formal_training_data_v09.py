from pathlib import Path
import sys
import json

import numpy as np
import pytest
import torch

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def test_epoch_order_is_complete_deterministic_and_epoch_specific():
    from formal_training_data_v09 import epoch_order_v09

    first = epoch_order_v09(101, seed=100, epoch=1)
    repeated = epoch_order_v09(101, seed=100, epoch=1)
    second_epoch = epoch_order_v09(101, seed=100, epoch=2)

    assert first.dtype == np.int64
    assert np.array_equal(first, repeated)
    assert np.array_equal(np.sort(first), np.arange(101, dtype=np.int64))
    assert not np.array_equal(first, second_epoch)


def test_float32_normalization_is_subtract_then_divide_and_does_not_mutate_input():
    from formal_training_data_v09 import normalize_forcing_batch_v09

    values = np.ascontiguousarray(np.asarray([[[3.0, 5.0], [7.0, 9.0]]], dtype=np.float32))
    original = values.copy()
    scaler = {
        "dynamic_center_float64": [1.0, 1.0],
        "dynamic_scale_float64": [2.0, 4.0],
    }
    result = normalize_forcing_batch_v09(values, scaler)
    expected = np.asarray([[[1.0, 1.0], [3.0, 2.0]]], dtype=np.float32)

    assert np.array_equal(values, original)
    assert result.dtype == np.float32 and result.flags.c_contiguous
    assert result.tobytes() == expected.tobytes()


def test_normalization_rejects_layout_dtype_and_invalid_scale():
    from formal_training_data_v09 import FormalTrainingDataError, normalize_forcing_batch_v09

    scaler = {
        "dynamic_center_float64": [0.0, 0.0],
        "dynamic_scale_float64": [1.0, 1.0],
    }
    with pytest.raises(FormalTrainingDataError, match="layout"):
        normalize_forcing_batch_v09(np.zeros((1, 2, 2), dtype=np.float64), scaler)
    with pytest.raises(FormalTrainingDataError, match="scale"):
        normalize_forcing_batch_v09(
            np.zeros((1, 2, 2), dtype=np.float32),
            {
                **scaler, "dynamic_scale_float64": [1.0, 0.0]
            },
        )


def test_target_normalization_and_masked_nse_loss_match_frozen_formula():
    from formal_training_data_v09 import (
        masked_nse_training_loss_v09,
        normalize_target_batch_v09,
    )

    raw = np.asarray([3.0, 7.0], dtype=np.float32)
    normalized = normalize_target_batch_v09(
        raw,
        {
            "target_center_float64": 1.0,
            "target_scale_float64": 2.0
        },
    )
    assert normalized.tobytes() == np.asarray([1.0, 3.0], dtype=np.float32).tobytes()
    prediction = torch.tensor([2.0, 5.0], dtype=torch.float32)
    target = torch.tensor([1.0, 3.0], dtype=torch.float32)
    std = torch.tensor([0.9, 1.9], dtype=torch.float32)
    expected = torch.mean(torch.square(prediction - target) / torch.square(std + 0.1))
    assert torch.equal(masked_nse_training_loss_v09(prediction, target, std), expected)


def test_ordered_training_keys_follow_basin_then_target_date_order():
    from formal_training_data_v09 import FormalTrainingInputsV09, ordered_training_keys_v09

    inputs = FormalTrainingInputsV09.synthetic(
        forcing=np.zeros((2, 10, 5), dtype=np.float32),
        statics=np.zeros((2, 27), dtype=np.float32),
        targets=np.ones((2, 3), dtype=np.float32),
        dates=np.arange("2000-01-01", "2000-01-11", dtype="datetime64[D]"),
        target_dates=np.arange("2000-01-08", "2000-01-11", dtype="datetime64[D]"),
    )
    basins, targets = ordered_training_keys_v09(inputs)

    assert np.array_equal(basins, np.asarray([0, 0, 0, 1, 1, 1], dtype=np.int64))
    assert np.array_equal(targets, np.asarray([7, 8, 9, 7, 8, 9], dtype=np.int64))


def test_recent_batch_and_full_window_recent_slice_are_byte_identical():
    from formal_training_data_v09 import FormalTrainingInputsV09, load_training_batch_v09

    forcing = np.arange(2 * 3562 * 5, dtype=np.float32).reshape(2, 3562, 5)
    inputs = FormalTrainingInputsV09.synthetic(
        forcing=forcing,
        statics=np.zeros((2, 27), dtype=np.float32),
        targets=np.ones((2, 1), dtype=np.float32),
        dates=np.arange("1990-01-01", "1999-10-03", dtype="datetime64[D]"),
        target_dates=np.asarray([np.datetime64("1999-10-02", "D")]),
        scaler={
            "dynamic_center_float64": [0.0] * 5,
            "dynamic_scale_float64": [1.0] * 5,
            "target_center_float64": 0.0,
            "target_scale_float64": 1.0,
            "per_basin_target_scale_float64": [1.0, 1.0],
        },
    )
    basin_indices = np.asarray([0, 1], dtype=np.int64)
    target_indices = np.asarray([3561, 3561], dtype=np.int64)
    recent = load_training_batch_v09(
        inputs,
        basin_indices,
        target_indices,
        variant="classic_lstm_256_clean",
        device="cpu",
    )
    history = load_training_batch_v09(
        inputs,
        basin_indices,
        target_indices,
        variant="continuous_multiscale_history",
        device="cpu",
    )

    assert recent.dynamic["recent"].numpy().tobytes() == history.dynamic["recent"].numpy().tobytes()
    assert history.dynamic["history"].shape == (2, 120, 7)


def test_formal_loader_opens_only_normalized_read_only_model_arrays(tmp_path, monkeypatch):
    import formal_training_data_v09 as module

    input_root = tmp_path / "input_attempt_01"
    input_root.mkdir()
    (input_root / "basins.txt").write_text("00000001\n", encoding="utf-8")
    (input_root / "scaler.json").write_text("{}", encoding="utf-8")
    for name in ("dates.npy", "target_dates.npy", "forcing.npy", "statics.npy", "targets.npy"):
        (input_root / name).write_bytes(b"sealed normalized array")
    # This sealed provenance file is present but must never be passed to np.load().
    (input_root / "statics_raw.float64.npy").write_bytes(b"sealed raw statics")
    descriptors = [{
        "relative_path": path.name,
        "size_bytes": path.stat().st_size,
        "sha256": "a" * 64,
    } for path in sorted(input_root.iterdir())]
    (input_root / "seal.json").write_text(
        json.dumps({
            "status": "sealed",
            "sealed_files": descriptors,
            "sealed_files_sha256": module.canonical_sha256(descriptors),
        }),
        encoding="utf-8",
    )
    protocol = tmp_path / "protocol.json"
    protocol.write_text('{"formal_evaluation_target_access":false}', encoding="utf-8")
    external = tmp_path / "input_attempt_01.external_audit.json"
    external.write_text(
        json.dumps({
            "status": "complete_input_audit_passed",
            "audit_context": {
                "input_seal_sha256": "a" * 64
            },
        }),
        encoding="utf-8",
    )
    trusted = tmp_path / "input_attempt_01.trusted_source_external_audit.json"
    trusted.write_text(
        json.dumps({
            "status": "complete_trusted_training_target_audit",
            "complete_input_external_audit_sha256": "a" * 64,
        }),
        encoding="utf-8",
    )
    arrays = {
        "dates.npy": np.arange("2000-01-01", "2000-01-03", dtype="datetime64[D]"),
        "target_dates.npy": np.asarray([np.datetime64("2000-01-02", "D")]),
        "forcing.npy": np.zeros((1, 2, 5), dtype=np.float32),
        "statics.npy": np.zeros((1, 27), dtype=np.float32),
        "targets.npy": np.ones((1, 1), dtype=np.float32),
    }
    opened = []

    def fake_load(path, *, mmap_mode, allow_pickle):
        assert mmap_mode == "r"
        assert allow_pickle is False
        opened.append(Path(path).name)
        result = arrays[Path(path).name]
        result.flags.writeable = False
        return result

    monkeypatch.setattr(module.np, "load", fake_load)
    monkeypatch.setattr(module, "sha256_file", lambda path: "a" * 64)
    monkeypatch.setattr(module, "array_payload_sha256", lambda values: module.STATIC_NORMALIZED_FLOAT32_SHA256)
    monkeypatch.setattr(module, "_validate_training_arrays_v09", lambda *args, **kwargs: None)

    loaded = module.load_sealed_training_inputs_v09(input_root, protocol)

    assert opened == [
        "dates.npy",
        "target_dates.npy",
        "forcing.npy",
        "statics.npy",
        "targets.npy",
    ]
    assert all(not values.flags.writeable for values in (
        loaded.dates,
        loaded.target_dates,
        loaded.forcing,
        loaded.statics,
        loaded.targets,
    ))

    (input_root / "answers_obs_eval.parquet").write_bytes(b"forbidden extra file")
    opened.clear()
    with pytest.raises(module.FormalTrainingDataError, match="directory file inventory"):
        module.load_sealed_training_inputs_v09(input_root, protocol)
    assert opened == []


def test_formal_loader_fails_before_arrays_when_external_audit_is_missing(tmp_path, monkeypatch):
    import formal_training_data_v09 as module

    input_root = tmp_path / "input_attempt_01"
    input_root.mkdir()
    protocol = tmp_path / "protocol.json"
    protocol.write_text('{"formal_evaluation_target_access":false}', encoding="utf-8")
    monkeypatch.setattr(
        module.np,
        "load",
        lambda *args, **kwargs: pytest.fail("array opened before external audit validation"),
    )

    with pytest.raises(module.FormalTrainingDataError, match="external audit is missing"):
        module.load_sealed_training_inputs_v09(input_root, protocol)


@pytest.mark.parametrize(
    "changed_name",
    [
        "basins.txt",
        "dates.npy",
        "target_dates.npy",
        "forcing.npy",
        "statics.npy",
        "targets.npy",
        "scaler.json",
    ],
)
def test_consumed_sealed_file_drift_fails_before_array_open(tmp_path, changed_name):
    import formal_training_data_v09 as module

    root = tmp_path / "input_attempt_01"
    root.mkdir()
    for name in (
            "basins.txt",
            "dates.npy",
            "target_dates.npy",
            "forcing.npy",
            "statics.npy",
            "targets.npy",
            "scaler.json",
            "statics_raw.float64.npy",
    ):
        (root / name).write_bytes(f"sealed:{name}".encode("utf-8"))
    descriptors = [{
        "relative_path": path.name,
        "size_bytes": path.stat().st_size,
        "sha256": module.sha256_file(path),
    } for path in sorted(root.iterdir())]
    seal = {
        "sealed_files": descriptors,
        "sealed_files_sha256": module.canonical_sha256(descriptors),
    }
    (root / "seal.json").write_text("{}", encoding="utf-8")
    module._verify_consumed_input_files_v09(root, seal)

    with (root / changed_name).open("ab") as handle:
        handle.write(b"drift")
    with pytest.raises(module.FormalTrainingDataError, match="file drift"):
        module._verify_consumed_input_files_v09(root, seal)
