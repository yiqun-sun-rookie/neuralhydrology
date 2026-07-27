from pathlib import Path
import hashlib
import json
import sys

import numpy as np
import pandas as pd
import pytest
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from diagnostics_v06 import (
    BRANCH_COMBINATIONS,
    DEFAULT_BRANCH_WIDTHS,
    capture_fused_features,
    masked_predictions_from_fused,
)
from data import DataPack, compute_scaler, default_periods, normalize_pack, split_target_indices
from models_v05 import build_model_v05
from metrics import per_basin_nse
from run_mask_diagnostic_v06 import run_mask_diagnostic_v06, validate_mask_config_v06
from train_v05 import _limited_balanced_indices, dynamic_batch_v05


EXPECTED_COMBINATIONS = (
    ("recent",),
    ("medium",),
    ("old",),
    ("recent", "medium"),
    ("recent", "old"),
    ("medium", "old"),
    ("recent", "medium", "old"),
)


def _inputs(batch_size: int = 3) -> tuple[dict[str, torch.Tensor], torch.Tensor]:
    generator = torch.Generator().manual_seed(610)
    dynamic = {
        "recent": torch.randn(batch_size, 270, 5, generator=generator),
        "medium": torch.randn(batch_size, 60, 20, generator=generator),
        "old": torch.randn(batch_size, 5, 12, 20, generator=generator),
    }
    statics = torch.randn(batch_size, 27, generator=generator)
    return dynamic, statics


def _synthetic_pack() -> DataPack:
    periods = default_periods()
    dates = pd.date_range(periods.history_start, periods.validation_end, freq="D")
    generator = np.random.default_rng(906)
    forcing = generator.normal(size=(1, len(dates), 5)).astype(np.float32)
    time = np.arange(len(dates), dtype=np.float32)
    discharge = (
        2.0
        + 0.5 * np.sin(time / 13.0)
        + 0.1 * forcing[0, :, 0]
    )[None, :].astype(np.float32)
    statics = generator.normal(size=(1, 27)).astype(np.float32)
    return DataPack(
        basins=("00000001",),
        dates=dates,
        forcing=forcing,
        discharge=discharge,
        statics=statics,
    )


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _source_run(tmp_path: Path, pack: DataPack) -> Path:
    source = tmp_path / "source"
    source.mkdir()
    scaler = compute_scaler(pack.forcing, pack.discharge, pack.statics, pack.dates)
    normalized = normalize_pack(pack, scaler)
    model = build_model_v05("hierarchical_rich_history", seed=100).eval()
    validation_basins, validation_times = split_target_indices(
        pack.dates,
        pack.discharge,
        split="validation",
    )
    validation_basins, validation_times = _limited_balanced_indices(
        validation_basins,
        validation_times,
        8,
    )
    forcing = torch.tensor(normalized.forcing)
    statics = torch.tensor(normalized.statics)
    basin_index = torch.tensor(validation_basins)
    target_index = torch.tensor(validation_times)
    dynamic = dynamic_batch_v05(
        "hierarchical_rich_history",
        forcing,
        basin_index,
        target_index,
    )
    with torch.no_grad():
        prediction = model(dynamic, statics[basin_index]).prediction.numpy()
    qsim = prediction * float(scaler["q_scale"]) + float(scaler["q_center"])
    predictions = pd.DataFrame({
        "basin": [pack.basins[index] for index in validation_basins],
        "date": pack.dates[validation_times].strftime("%Y-%m-%d"),
        "qobs": pack.discharge[validation_basins, validation_times],
        "qsim": qsim,
    })
    torch.save(
        {
            "model_state_dict": model.state_dict(),
            "variant": "hierarchical_rich_history",
            "seed": 100,
            "parameter_count": 455_105,
            "scaler": scaler,
        },
        source / "checkpoint.pt",
    )
    predictions.to_csv(source / "predictions.csv", index=False)
    manifest = {
        "status": "complete",
        "variant": "hierarchical_rich_history",
        "seed": 100,
        "parameter_count": 455_105,
        "n_validation_predictions": 8,
        "data_access": {"raw_observed_discharge_reads": 0},
        "artifacts": {
            "checkpoint.pt": _sha256(source / "checkpoint.pt"),
            "predictions.csv": _sha256(source / "predictions.csv"),
        },
    }
    (source / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    return source


def _runner_config(source: Path) -> dict:
    checkpoint = source / "checkpoint.pt"
    predictions = source / "predictions.csv"
    return {
        "experiment_id": "D06-MASK",
        "experiment_family": "strict_branch_masking_v06",
        "mode": "smoke",
        "basin_file_sha256": "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65",
        "target_bundle_sha256": "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c",
        "validation_start": "2006-10-01",
        "validation_end": "2008-09-30",
        "validation_batch_size": 4,
        "limit_validation_samples": 8,
        "source_variant": "hierarchical_rich_history",
        "source_seed": 100,
        "source_checkpoint_sha256": _sha256(checkpoint) if checkpoint.exists() else "a" * 64,
        "source_predictions_sha256": _sha256(predictions) if predictions.exists() else "b" * 64,
        "results_root": "results/26_historical_band_experts/strict_branch_masking_v06",
        "formal_evaluation_access": False,
    }


def test_v06_branch_combinations_are_exactly_the_seven_nonempty_subsets():
    assert BRANCH_COMBINATIONS == EXPECTED_COMBINATIONS
    assert DEFAULT_BRANCH_WIDTHS == {
        "recent": 256,
        "medium": 64,
        "old": 128,
    }


def test_v06_all_branch_mask_exactly_matches_original_v05_forward():
    dynamic, statics = _inputs()
    model = build_model_v05("hierarchical_rich_history", seed=100).eval()

    original, fused = capture_fused_features(model, dynamic, statics)
    masked = masked_predictions_from_fused(model, fused)

    torch.testing.assert_close(
        masked[("recent", "medium", "old")],
        original,
        rtol=0,
        atol=0,
    )


def test_v06_inactive_features_are_zeroed_after_encoding_and_bias_is_retained_once():
    model = build_model_v05("hierarchical_rich_history", seed=100).eval()
    with torch.no_grad():
        model.head.weight.fill_(1.0)
        model.head.bias.fill_(3.0)
    fused = torch.ones(2, 448)

    masked = masked_predictions_from_fused(model, fused)

    torch.testing.assert_close(masked[("recent",)], torch.full((2,), 259.0))
    torch.testing.assert_close(masked[("medium",)], torch.full((2,), 67.0))
    torch.testing.assert_close(masked[("old",)], torch.full((2,), 131.0))
    torch.testing.assert_close(masked[("recent", "medium")], torch.full((2,), 323.0))
    torch.testing.assert_close(masked[("recent", "old")], torch.full((2,), 387.0))
    torch.testing.assert_close(masked[("medium", "old")], torch.full((2,), 195.0))
    torch.testing.assert_close(masked[("recent", "medium", "old")], torch.full((2,), 451.0))


def test_v06_capture_rejects_training_mode_because_dropout_would_change_mask_semantics():
    dynamic, statics = _inputs()
    model = build_model_v05("hierarchical_rich_history", seed=100).train()

    with pytest.raises(ValueError, match="evaluation mode"):
        capture_fused_features(model, dynamic, statics)


def test_v06_masking_rejects_wrong_fused_width():
    model = build_model_v05("hierarchical_rich_history", seed=100).eval()

    with pytest.raises(ValueError, match="448"):
        masked_predictions_from_fused(model, torch.zeros(2, 447))


def test_v06_tiny_mask_runner_uses_checkpoint_scaler_and_writes_recomputable_artifacts(tmp_path):
    pack = _synthetic_pack()
    source = _source_run(tmp_path, pack)
    output = tmp_path / "output"

    manifest = run_mask_diagnostic_v06(
        pack=pack,
        config=_runner_config(source),
        source_run=source,
        output_dir=output,
        device="cpu",
    )

    assert manifest["status"] == "complete"
    assert manifest["n_validation_predictions"] == 8
    assert manifest["all_branch_exact_match"] is True
    assert manifest["scaler_source"] == "checkpoint.pt"
    assert manifest["data_access"] == {
        "raw_observed_discharge_reads": 0,
        "target_bundle_interface": True,
        "formal_evaluation_access": False,
    }
    assert {path.name for path in output.iterdir()} == {
        "config.json",
        "predictions.csv",
        "per_basin_metrics.csv",
        "summary.json",
        "manifest.json",
    }
    predictions = pd.read_csv(output / "predictions.csv", dtype={"basin": str})
    assert len(predictions) == 8
    assert predictions.filter(like="qsim_").shape[1] == 7
    metrics = pd.read_csv(output / "per_basin_metrics.csv", dtype={"basin": str})
    assert len(metrics) == 7
    assert np.isfinite(metrics["nse"]).all()
    recomputed_parts = []
    for column in predictions.filter(like="qsim_"):
        label = column.removeprefix("qsim_")
        recomputed = per_basin_nse(
            predictions[["basin", "date", "qobs", column]].rename(columns={column: "qsim"})
        )
        recomputed.insert(0, "combination", label)
        recomputed_parts.append(recomputed)
    pd.testing.assert_frame_equal(
        metrics,
        pd.concat(recomputed_parts, ignore_index=True),
        check_exact=True,
    )
    for name, expected in manifest["artifacts"].items():
        assert _sha256(output / name) == expected
    assert not list(output.glob("*.tmp"))


def test_v06_mask_runner_rejects_nonempty_output_and_preserves_foreign_file(tmp_path):
    pack = _synthetic_pack()
    source = _source_run(tmp_path, pack)
    output = tmp_path / "output"
    output.mkdir()
    foreign = output / "foreign.txt"
    foreign.write_text("preserve", encoding="utf-8")

    with pytest.raises(FileExistsError, match="not empty"):
        run_mask_diagnostic_v06(
            pack=pack,
            config=_runner_config(source),
            source_run=source,
            output_dir=output,
            device="cpu",
        )
    assert foreign.read_text(encoding="utf-8") == "preserve"


@pytest.mark.parametrize(
    ("key", "bad_value", "message"),
    [
        ("validation_start", "1989-10-01", "validation_start"),
        ("validation_end", "1999-09-30", "validation_end"),
        ("target_bundle_sha256", "0" * 64, "target_bundle_sha256"),
        ("formal_evaluation_access", True, "formal_evaluation_access"),
        ("source_run_dir", "results/usgs_streamflow", "forbidden"),
    ],
)
def test_v06_mask_config_rejects_date_hash_access_or_forbidden_path(key, bad_value, message):
    config = _runner_config(Path("."))
    config[key] = bad_value
    with pytest.raises(ValueError, match=message):
        validate_mask_config_v06(config)


def test_v06_mask_runner_rejects_changed_source_checkpoint(tmp_path):
    pack = _synthetic_pack()
    source = _source_run(tmp_path, pack)
    config = _runner_config(source)
    with (source / "checkpoint.pt").open("ab") as handle:
        handle.write(b"tamper")

    with pytest.raises(ValueError, match="checkpoint SHA-256"):
        run_mask_diagnostic_v06(
            pack=pack,
            config=config,
            source_run=source,
            output_dir=tmp_path / "output",
            device="cpu",
        )
