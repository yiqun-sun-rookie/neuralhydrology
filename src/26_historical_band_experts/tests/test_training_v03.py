from pathlib import Path
import hashlib
import json
import sys

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from data import DataPack, default_periods
from metrics import per_basin_nse
from models_v03 import VARIANTS_V03
import train_v03


EXPECTED_PARAMETER_COUNTS = {
    "classic_lstm_256": 297_217,
    "classic_lstm_261": 308_242,
    "classic_lstm_266": 319_467,
    "late_concat": 308_401,
    "initial_memory": 320_897,
}


def _synthetic_pack() -> DataPack:
    periods = default_periods()
    dates = pd.date_range(periods.history_start, periods.validation_end, freq="D")
    generator = np.random.default_rng(41)
    forcing = generator.normal(size=(1, len(dates), 5)).astype(np.float32)
    time = np.arange(len(dates), dtype=np.float32)
    discharge = (
        2.0
        + 0.6 * np.sin(time / 17.0)
        + 0.2 * forcing[0, :, 0]
    )[None, :].astype(np.float32)
    statics = generator.normal(size=(1, 27)).astype(np.float32)
    return DataPack(
        basins=("00000001",),
        dates=dates,
        forcing=forcing,
        discharge=discharge,
        statics=statics,
    )


def _config() -> dict:
    return {
        "experiment_family": "classic_lstm_historical_context_v03_smoke",
        "mode": "smoke",
        "epochs": 2,
        "batch_size": 256,
        "validation_batch_size": 4,
        "learning_rate_schedule": {"1": 0.001, "12": 0.0005, "22": 0.0001},
        "gradient_clip": 1.0,
        "recent_hidden_size": 256,
        "history_hidden_size": 24,
        "initial_forget_bias": 5.0,
        "output_dropout": 0.4,
        "limit_batches": 1,
        "limit_validation_samples": 8,
    }


def test_v03_learning_rate_schedule_matches_classic_training():
    config = _config()
    expected = {
        1: 0.001,
        11: 0.001,
        12: 0.0005,
        21: 0.0005,
        22: 0.0001,
        30: 0.0001,
    }
    assert {epoch: train_v03.learning_rate_for_epoch(config, epoch) for epoch in expected} == expected


def test_v03_dynamic_batch_exposes_only_inputs_consumed_by_each_arm():
    forcing = train_v03.torch.zeros((1, 4000, 5))
    prefix = train_v03.forcing_prefix(forcing)
    basins = train_v03.torch.tensor([0])
    targets = train_v03.torch.tensor([3649])

    for variant in ("classic_lstm_256", "classic_lstm_261", "classic_lstm_266"):
        dynamic = train_v03.dynamic_batch_v03(variant, forcing, prefix, basins, targets)
        assert tuple(dynamic) == ("recent",)
        assert dynamic["recent"].shape == (1, 270, 5)

    for variant in ("late_concat", "initial_memory"):
        dynamic = train_v03.dynamic_batch_v03(variant, forcing, prefix, basins, targets)
        assert tuple(dynamic) == ("recent", "medium", "old")


@pytest.mark.parametrize("variant", VARIANTS_V03)
def test_v03_tiny_run_writes_atomic_recomputable_artifacts(tmp_path, variant):
    output_dir = tmp_path / f"{variant}_s100"
    manifest = train_v03.run_experiment_v03(
        pack=_synthetic_pack(),
        config=_config(),
        variant=variant,
        seed=100,
        output_dir=output_dir,
        device="cpu",
    )

    expected = {
        "config.json",
        "checkpoint.pt",
        "predictions.csv",
        "per_basin_metrics.csv",
        "manifest.json",
    }
    assert expected == {path.name for path in output_dir.iterdir()}
    assert manifest["status"] == "complete"
    assert manifest["variant"] == variant
    assert manifest["seed"] == 100
    assert manifest["parameter_count"] == EXPECTED_PARAMETER_COUNTS[variant]
    assert manifest["epoch_learning_rates"] == [0.001, 0.001]
    assert manifest["data_access"]["raw_observed_discharge_reads"] == 0
    assert manifest["optimizer_steps_total"] == 2
    assert np.isfinite(manifest["final_training_loss"])
    assert not list(output_dir.glob("*.tmp"))

    predictions = pd.read_csv(output_dir / "predictions.csv", dtype={"basin": str})
    saved = pd.read_csv(output_dir / "per_basin_metrics.csv", dtype={"basin": str})
    recomputed = per_basin_nse(predictions)
    pd.testing.assert_frame_equal(saved, recomputed, check_exact=True)
    assert set(manifest["artifacts"]) == {
        "config.json",
        "checkpoint.pt",
        "predictions.csv",
        "per_basin_metrics.csv",
    }


def test_v03_existing_output_directory_cannot_be_overwritten(tmp_path):
    output_dir = tmp_path / "classic_lstm_256_s100"
    output_dir.mkdir()
    (output_dir / "foreign.txt").write_text("preserve", encoding="utf-8")
    with pytest.raises(FileExistsError, match="not empty"):
        train_v03.run_experiment_v03(
            pack=_synthetic_pack(),
            config=_config(),
            variant="classic_lstm_256",
            seed=100,
            output_dir=output_dir,
            device="cpu",
        )
    assert (output_dir / "foreign.txt").read_text(encoding="utf-8") == "preserve"


def test_v03_runner_rejects_unknown_variant(tmp_path):
    with pytest.raises(ValueError, match="variant"):
        train_v03.run_experiment_v03(
            pack=_synthetic_pack(),
            config=_config(),
            variant="unknown",
            seed=100,
            output_dir=tmp_path / "unknown",
            device="cpu",
        )


@pytest.mark.parametrize(
    ("key", "bad_value"),
    [
        ("batch_size", 128),
        ("recent_hidden_size", 255),
        ("history_hidden_size", 25),
        ("initial_forget_bias", 4.0),
        ("output_dropout", 0.3),
        ("gradient_clip", 2.0),
        ("learning_rate_schedule", {"1": 0.001}),
    ],
)
def test_v03_frozen_config_rejects_architecture_or_training_drift(key, bad_value):
    config = _config()
    config[key] = bad_value
    with pytest.raises(ValueError, match=key):
        train_v03.validate_frozen_config_v03(config)


def test_v03_pilot_requires_thirty_epochs_and_unlimited_batches():
    config = _config()
    config.update({"mode": "pilot", "epochs": 29, "limit_batches": 0, "limit_validation_samples": 0})
    with pytest.raises(ValueError, match="epochs"):
        train_v03.validate_frozen_config_v03(config)

    config["epochs"] = 30
    train_v03.validate_frozen_config_v03(config)


def test_v03_frozen_file_hash_validation_rejects_changed_file(tmp_path):
    path = tmp_path / "basins.txt"
    path.write_text("00000001\n", encoding="utf-8")
    expected = hashlib.sha256(path.read_bytes()).hexdigest()
    assert train_v03.validate_frozen_file_hash(path, expected, "basin list") == expected

    path.write_text("00000002\n", encoding="utf-8")
    with pytest.raises(ValueError, match="basin list SHA-256"):
        train_v03.validate_frozen_file_hash(path, expected, "basin list")


def test_v03_config_snapshot_records_variant_and_seed(tmp_path):
    output_dir = tmp_path / "classic_lstm_256_s100"
    train_v03.run_experiment_v03(
        pack=_synthetic_pack(),
        config=_config(),
        variant="classic_lstm_256",
        seed=100,
        output_dir=output_dir,
        device="cpu",
    )
    snapshot = json.loads((output_dir / "config.json").read_text(encoding="utf-8"))
    assert snapshot["variant"] == "classic_lstm_256"
    assert snapshot["seed"] == 100
