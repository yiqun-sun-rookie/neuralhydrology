from pathlib import Path
import hashlib
import sys

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from analyze_equal_experts_v06 import evaluate_stage1_equal_v06
from data import DataPack, default_periods
from metrics import per_basin_nse
from models_equal_experts_v06 import VARIANTS_EQUAL_EXPERTS_V06
from train_equal_experts_v06 import (
    dynamic_batch_equal_v06,
    run_equal_experiment_v06,
    validate_equal_config_v06,
)


def _synthetic_pack() -> DataPack:
    periods = default_periods()
    dates = pd.date_range(periods.history_start, periods.validation_end, freq="D")
    generator = np.random.default_rng(816)
    forcing = generator.normal(size=(1, len(dates), 5)).astype(np.float32)
    time = np.arange(len(dates), dtype=np.float32)
    discharge = (
        2.0
        + 0.5 * np.sin(time / 17.0)
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


def _config() -> dict:
    return {
        "experiment_id": "E06-I01",
        "experiment_family": "equal_historical_experts_i01_v06",
        "candidate_iteration": 1,
        "candidate_iteration_budget": 5,
        "mode": "smoke",
        "basin_file_sha256": "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65",
        "target_bundle_sha256": "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c",
        "strict_nesting_summary_sha256": "38cb81e24d575e8291fa04f0a530de2baf45ad9e32fcb8bdf524f9f61b780f2d",
        "results_root": "results/26_historical_band_experts/equal_experts_i01_v06_smoke",
        "epochs": 2,
        "batch_size": 4,
        "validation_batch_size": 4,
        "learning_rate_schedule": {"1": 0.001, "12": 0.0005, "22": 0.0001},
        "gradient_clip": 1.0,
        "initial_forget_bias": 5.0,
        "output_dropout": 0.4,
        "dropout_stream": "seed_epoch_batch_branch_sha256",
        "recent_hidden_size": 256,
        "medium_hidden_size": 256,
        "old_hidden_size": 256,
        "capacity_control_hidden_size": 455,
        "recent_lags": [0, 269],
        "medium_lags": [270, 1824],
        "old_lags": [1825, 3649],
        "medium_bins": 60,
        "old_bins": 60,
        "history_statistics": ["mean"],
        "candidate_parameter_count": 891_649,
        "capacity_control_parameter_count": 890_436,
        "seeds": [100, 200, 300],
        "stage1_seed": 100,
        "stage1_gates": {
            "median_delta_classic_at_least": 0.01,
            "median_delta_capacity_above": 0.0,
            "median_delta_late_concat_above": 0.0,
            "win_fraction_classic_at_least": 0.55,
        },
        "limit_batches": 1,
        "limit_validation_samples": 8,
        "formal_evaluation_access": False,
    }


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_v06_dynamic_batches_use_exact_frozen_recent_and_mean_history_bands():
    forcing = np.arange(4000 * 5, dtype=np.float32).reshape(1, 4000, 5)
    import torch
    forcing_tensor = torch.tensor(forcing)
    prefix = torch.cat(
        (torch.zeros(1, 1, 5), torch.cumsum(forcing_tensor, dim=1)),
        dim=1,
    )
    basins = torch.tensor([0])
    targets = torch.tensor([3649])

    classic = dynamic_batch_equal_v06(
        "classic_lstm_256_keyed", forcing_tensor, prefix, basins, targets
    )
    candidate = dynamic_batch_equal_v06(
        "equal_experts", forcing_tensor, prefix, basins, targets
    )

    assert tuple(classic) == ("recent",)
    assert classic["recent"].shape == (1, 270, 5)
    assert tuple(candidate) == ("recent", "medium", "old")
    assert candidate["recent"].shape == (1, 270, 5)
    assert candidate["medium"].shape == (1, 60, 5)
    assert candidate["old"].shape == (1, 60, 5)


@pytest.mark.parametrize("variant", VARIANTS_EQUAL_EXPERTS_V06)
def test_v06_tiny_equal_expert_run_writes_atomic_recomputable_artifacts(tmp_path, variant):
    output = tmp_path / variant

    manifest = run_equal_experiment_v06(
        pack=_synthetic_pack(),
        config=_config(),
        variant=variant,
        seed=100,
        output_dir=output,
        device="cpu",
    )

    assert manifest["status"] == "complete"
    assert manifest["optimizer_steps_total"] == 2
    assert manifest["n_validation_predictions"] == 8
    assert manifest["dropout_stream"] == "seed_epoch_batch_branch_sha256"
    assert manifest["data_access"]["formal_evaluation_access"] is False
    assert {path.name for path in output.iterdir()} == {
        "config.json",
        "checkpoint.pt",
        "predictions.csv",
        "per_basin_metrics.csv",
        "manifest.json",
    }
    predictions = pd.read_csv(output / "predictions.csv", dtype={"basin": str})
    metrics = pd.read_csv(output / "per_basin_metrics.csv", dtype={"basin": str})
    pd.testing.assert_frame_equal(metrics, per_basin_nse(predictions), check_exact=True)
    for name, expected in manifest["artifacts"].items():
        assert _sha256(output / name) == expected


@pytest.mark.parametrize(
    ("key", "value"),
    [
        ("candidate_iteration", 2),
        ("candidate_iteration_budget", 6),
        ("dropout_stream", "global"),
        ("medium_hidden_size", 128),
        ("capacity_control_hidden_size", 456),
        ("history_statistics", ["mean", "max"]),
        ("formal_evaluation_access", True),
    ],
)
def test_v06_equal_config_rejects_iteration_architecture_or_access_drift(key, value):
    config = _config()
    config[key] = value
    with pytest.raises(ValueError, match=key):
        validate_equal_config_v06(config)


def test_v06_stage1_gate_uses_paired_basin_differences():
    paired = pd.DataFrame({
        "basin": ["a", "b", "c", "d"],
        "nse_classic": [0.50, 0.60, 0.70, 0.80],
        "nse_capacity": [0.50, 0.60, 0.70, 0.80],
        "nse_late_concat": [0.50, 0.60, 0.70, 0.80],
        "nse_candidate": [0.52, 0.62, 0.72, 0.82],
    })

    result = evaluate_stage1_equal_v06(paired, _config()["stage1_gates"])

    assert result["passed"] is True
    assert result["median_delta_classic"] == pytest.approx(0.02)
    assert result["median_delta_capacity"] == pytest.approx(0.02)
    assert result["median_delta_late_concat"] == pytest.approx(0.02)
    assert result["win_fraction_classic"] == 1.0
