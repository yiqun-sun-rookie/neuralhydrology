from pathlib import Path
import hashlib
import json
import sys

import numpy as np
import pandas as pd
import pytest
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from models_v06 import build_strict_pair_v06
from data import DataPack, default_periods
from train_strict_v06 import (
    StrictNestingMismatch,
    active_named_parameters,
    assert_batch_indices_equal,
    assert_exact_tensor,
    assert_parameter_sequence_equal,
    exact_evaluation_predictions,
    lockstep_train_step,
    run_strict_reproduction_v06,
    validate_strict_config_v06,
)


def _batch(device: str = "cpu"):
    generator = torch.Generator().manual_seed(706)
    dynamic = {
        "recent": torch.randn(3, 12, 5, generator=generator).to(device),
    }
    statics = torch.randn(3, 27, generator=generator).to(device)
    target = torch.randn(3, generator=generator).to(device)
    weights = torch.tensor([0.5, 1.0, 1.5], device=device)
    basins = torch.tensor([0, 1, 2], device=device)
    times = torch.tensor([3649, 3650, 3651], device=device)
    return dynamic, statics, target, weights, basins, times


def _optimizers(classic, nested):
    return (
        torch.optim.Adam((parameter for _, parameter in active_named_parameters(classic)), lr=0.001),
        torch.optim.Adam((parameter for _, parameter in active_named_parameters(nested)), lr=0.001),
    )


def _synthetic_pack() -> DataPack:
    periods = default_periods()
    dates = pd.date_range(periods.history_start, periods.validation_end, freq="D")
    generator = np.random.default_rng(716)
    forcing = generator.normal(size=(1, len(dates), 5)).astype(np.float32)
    time = np.arange(len(dates), dtype=np.float32)
    discharge = (
        1.5
        + 0.4 * np.sin(time / 11.0)
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


def _strict_config() -> dict:
    return {
        "experiment_id": "R06-NEST",
        "experiment_family": "strict_nesting_v06",
        "mode": "smoke",
        "basin_file_sha256": "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65",
        "target_bundle_sha256": "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c",
        "validation_start": "2006-10-01",
        "validation_end": "2008-09-30",
        "results_root": "results/26_historical_band_experts/strict_nesting_v06",
        "seed": 100,
        "epochs": 2,
        "batch_size": 4,
        "validation_batch_size": 4,
        "learning_rate_schedule": {"1": 0.001, "12": 0.0005, "22": 0.0001},
        "gradient_clip": 1.0,
        "recent_hidden_size": 256,
        "initial_forget_bias": 5.0,
        "output_dropout": 0.4,
        "reproduction_tolerance": {"absolute": 0.0, "relative": 0.0},
        "candidate_iteration_budget": 5,
        "limit_batches": 1,
        "limit_validation_samples": 8,
        "formal_evaluation_access": False,
    }


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_v06_lockstep_step_keeps_predictions_gradients_adam_and_parameters_exact():
    classic, nested = build_strict_pair_v06(seed=100)
    optimizers = _optimizers(classic, nested)
    dynamic, statics, target, weights, basins, times = _batch()

    report = lockstep_train_step(
        classic=classic,
        nested=nested,
        classic_optimizer=optimizers[0],
        nested_optimizer=optimizers[1],
        dynamic=dynamic,
        statics=statics,
        target=target,
        loss_weights=weights,
        basin_indices=(basins, basins.clone()),
        target_indices=(times, times.clone()),
        gradient_clip=1.0,
    )

    assert report["status"] == "exact"
    assert report["prediction_equal"] is True
    assert report["loss_equal"] is True
    assert report["gradients_equal"] is True
    assert report["optimizer_state_equal"] is True
    assert report["parameters_equal"] is True
    for (_, classic_parameter), (_, nested_parameter) in zip(
        active_named_parameters(classic),
        active_named_parameters(nested),
    ):
        assert torch.equal(classic_parameter, nested_parameter)


def test_v06_two_lockstep_steps_remain_exact():
    classic, nested = build_strict_pair_v06(seed=100)
    optimizers = _optimizers(classic, nested)
    dynamic, statics, target, weights, basins, times = _batch()

    for _ in range(2):
        report = lockstep_train_step(
            classic=classic,
            nested=nested,
            classic_optimizer=optimizers[0],
            nested_optimizer=optimizers[1],
            dynamic=dynamic,
            statics=statics,
            target=target,
            loss_weights=weights,
            basin_indices=(basins, basins.clone()),
            target_indices=(times, times.clone()),
            gradient_clip=1.0,
        )
        assert report["status"] == "exact"


def test_v06_two_synthetic_epochs_and_final_evaluation_predictions_remain_exact():
    classic, nested = build_strict_pair_v06(seed=100)
    optimizers = _optimizers(classic, nested)
    dynamic, statics, target, weights, basins, times = _batch()

    for _epoch in range(2):
        for _batch_index in range(2):
            lockstep_train_step(
                classic=classic,
                nested=nested,
                classic_optimizer=optimizers[0],
                nested_optimizer=optimizers[1],
                dynamic=dynamic,
                statics=statics,
                target=target,
                loss_weights=weights,
                basin_indices=(basins, basins.clone()),
                target_indices=(times, times.clone()),
                gradient_clip=1.0,
            )

    classic_predictions, nested_predictions = exact_evaluation_predictions(
        classic,
        nested,
        [(dynamic, statics), (dynamic, statics)],
    )
    assert torch.equal(classic_predictions, nested_predictions)


def test_v06_changed_batch_index_fails_before_forward():
    _dynamic, _statics, _target, _weights, basins, times = _batch()
    changed = times.clone()
    changed[0] += 1

    with pytest.raises(StrictNestingMismatch, match="target batch indices"):
        assert_batch_indices_equal(
            basin_indices=(basins, basins.clone()),
            target_indices=(times, changed),
        )


def test_v06_changed_parameter_order_fails_before_training():
    classic, nested = build_strict_pair_v06(seed=100)
    classic_parameters = active_named_parameters(classic)
    nested_parameters = list(reversed(active_named_parameters(nested)))

    with pytest.raises(StrictNestingMismatch, match="parameter order"):
        assert_parameter_sequence_equal(classic_parameters, nested_parameters)


def test_v06_changed_dropout_mask_reports_the_first_differing_component():
    reference = torch.tensor([[1.0, 0.0], [0.0, 1.0]])
    changed = reference.clone()
    changed[0, 0] = 0.0

    with pytest.raises(StrictNestingMismatch, match="dropout mask"):
        assert_exact_tensor("dropout mask", reference, changed)


@pytest.mark.skipif(not torch.cuda.is_available(), reason="CUDA is required")
def test_v06_cuda_lockstep_step_is_exact():
    classic, nested = build_strict_pair_v06(seed=100)
    classic = classic.cuda()
    nested = nested.cuda()
    optimizers = _optimizers(classic, nested)
    dynamic, statics, target, weights, basins, times = _batch(device="cuda")

    report = lockstep_train_step(
        classic=classic,
        nested=nested,
        classic_optimizer=optimizers[0],
        nested_optimizer=optimizers[1],
        dynamic=dynamic,
        statics=statics,
        target=target,
        loss_weights=weights,
        basin_indices=(basins, basins.clone()),
        target_indices=(times, times.clone()),
        gradient_clip=1.0,
    )

    assert report["status"] == "exact"


def test_v06_tiny_strict_reproduction_writes_exact_recomputable_evidence(tmp_path):
    output = tmp_path / "strict"

    manifest = run_strict_reproduction_v06(
        pack=_synthetic_pack(),
        config=_strict_config(),
        output_dir=output,
        device="cpu",
    )

    assert manifest["status"] == "complete_exact"
    assert manifest["lockstep_exact"] is True
    assert manifest["historical_reference_checked"] is False
    assert manifest["optimizer_steps_total"] == 2
    assert manifest["n_validation_predictions"] == 8
    assert manifest["active_parameter_count"] == 297_217
    assert {path.name for path in output.iterdir()} == {
        "config.json",
        "checkpoint.pt",
        "predictions.csv",
        "per_basin_metrics.csv",
        "summary.json",
        "manifest.json",
    }
    predictions = pd.read_csv(output / "predictions.csv", dtype={"basin": str})
    assert np.array_equal(
        predictions["qsim_classic"].to_numpy(dtype=np.float32),
        predictions["qsim_nested"].to_numpy(dtype=np.float32),
    )
    checkpoint = torch.load(output / "checkpoint.pt", map_location="cpu", weights_only=False)
    for name, classic_value in checkpoint["classic_state_dict"].items():
        if name in checkpoint["active_parameter_names"]:
            assert torch.equal(classic_value, checkpoint["nested_state_dict"][name])
    for name, expected in manifest["artifacts"].items():
        assert _sha256(output / name) == expected
    summary = json.loads((output / "summary.json").read_text(encoding="utf-8"))
    assert summary["maximum_prediction_absolute_difference"] == 0.0


@pytest.mark.parametrize(
    ("key", "value", "message"),
    [
        ("validation_start", "1989-10-01", "validation_start"),
        ("reproduction_tolerance", {"absolute": 1e-6, "relative": 0.0}, "reproduction_tolerance"),
        ("candidate_iteration_budget", 6, "candidate_iteration_budget"),
        ("formal_evaluation_access", True, "formal_evaluation_access"),
    ],
)
def test_v06_strict_config_rejects_protocol_drift(key, value, message):
    config = _strict_config()
    config[key] = value
    with pytest.raises(ValueError, match=message):
        validate_strict_config_v06(config)
