from pathlib import Path
import hashlib
import json
import sys

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import train
from data import DataPack, default_periods
from metrics import per_basin_nse
from train import run_experiment


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


def _config():
    return {
        "epochs": 1,
        "batch_size": 4,
        "validation_batch_size": 4,
        "learning_rate": 0.001,
        "gradient_clip": 1.0,
        "limit_batches": 1,
        "limit_validation_samples": 8,
    }


@pytest.mark.parametrize(
    "variant",
    ["mainstream_lstm", "multiscale_fusion", "historical_band_experts"],
)
def test_tiny_run_writes_atomic_recomputable_artifacts(tmp_path, variant):
    output_dir = tmp_path / f"{variant}_s100"

    manifest = run_experiment(
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
    assert expected.issubset({path.name for path in output_dir.iterdir()})
    assert manifest["status"] == "complete"
    assert manifest["variant"] == variant
    assert manifest["seed"] == 100
    assert np.isfinite(manifest["final_training_loss"])
    assert not list(output_dir.glob("*.tmp"))

    predictions = pd.read_csv(output_dir / "predictions.csv", dtype={"basin": str})
    saved = pd.read_csv(output_dir / "per_basin_metrics.csv", dtype={"basin": str})
    recomputed = per_basin_nse(predictions)
    pd.testing.assert_frame_equal(saved, recomputed, check_exact=True)

    snapshot = json.loads((output_dir / "config.json").read_text(encoding="utf-8"))
    assert snapshot["variant"] == variant
    assert snapshot["seed"] == 100


def test_existing_output_directory_cannot_be_overwritten(tmp_path):
    output_dir = tmp_path / "mainstream_lstm_s100"
    output_dir.mkdir()
    (output_dir / "foreign.txt").write_text("preserve", encoding="utf-8")

    with pytest.raises(FileExistsError, match="not empty"):
        run_experiment(
            pack=_synthetic_pack(),
            config=_config(),
            variant="mainstream_lstm",
            seed=100,
            output_dir=output_dir,
            device="cpu",
        )

    assert (output_dir / "foreign.txt").read_text(encoding="utf-8") == "preserve"


def test_per_basin_nse_matches_manual_value():
    frame = pd.DataFrame(
        {
            "basin": ["00000001"] * 3,
            "date": ["2007-01-01", "2007-01-02", "2007-01-03"],
            "qobs": [1.0, 2.0, 3.0],
            "qsim": [1.0, 2.0, 2.0],
        }
    )

    result = per_basin_nse(frame)

    assert result.loc[0, "basin"] == "00000001"
    assert result.loc[0, "nse"] == 0.5
    assert result.loc[0, "n_days"] == 3

def test_metric_csv_round_trip_is_exact(tmp_path):
    predictions = pd.DataFrame(
        {
            "basin": ["01644000"] * 3,
            "date": ["2006-10-01", "2006-10-02", "2006-10-03"],
            "qobs": [0.14801706, 0.1280917, 0.11955225],
            "qsim": [1.8289721, 1.9013839, 2.0032046],
        }
    )
    metrics = per_basin_nse(predictions)
    path = tmp_path / "metrics.csv"
    metrics.to_csv(path, index=False)
    reloaded = pd.read_csv(path, dtype={"basin": str})

    pd.testing.assert_frame_equal(metrics, reloaded, check_exact=True)

def test_frozen_file_hash_validation_rejects_changed_basin_list(tmp_path):
    path = tmp_path / "basins.txt"
    path.write_text("00000001\n", encoding="utf-8")
    expected = hashlib.sha256(path.read_bytes()).hexdigest()

    assert train.validate_frozen_file_hash(path, expected, "basin list") == expected
    path.write_text("00000002\n", encoding="utf-8")
    with pytest.raises(ValueError, match="basin list SHA-256"):
        train.validate_frozen_file_hash(path, expected, "basin list")
