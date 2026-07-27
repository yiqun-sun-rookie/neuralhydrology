import csv
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest
import torch

IDEA_ROOT = Path(__file__).resolve().parents[1]
CONFIG_ROOT = IDEA_ROOT / "configs"
REPO_ROOT = IDEA_ROOT.parents[1]
sys.path.insert(0, str(IDEA_ROOT))

from models_v03 import count_trainable_parameters
from data import DataPack, default_periods
from metrics import per_basin_nse


def _load(name: str) -> dict:
    return json.loads((CONFIG_ROOT / name).read_text(encoding="utf-8"))


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_v07_configs_freeze_sequential_state_transfer_protocol():
    pilot = _load("sequential_transfer_s01_v07.json")
    smoke = _load("sequential_transfer_s01_smoke_v07.json")

    for config in (pilot, smoke):
        assert config["experiment_id"] == "E07-S01"
        assert config["experiment_family"] == "sequential_coarse_to_fine_v07"
        assert config["basin_file_sha256"] == (
            "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65"
        )
        assert config["target_bundle_sha256"] == (
            "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c"
        )
        assert config["recent_lags"] == [0, 269]
        assert config["medium_lags"] == [270, 1824]
        assert config["old_lags"] == [1825, 3649]
        assert config["medium_bins"] == config["old_bins"] == 60
        assert config["recent_hidden_size"] == 256
        assert config["medium_hidden_size"] == 256
        assert config["old_hidden_size"] == 256
        assert config["candidate_parameter_count"] == 891_137
        assert config["capacity_control_parameter_count"] == 890_436
        assert config["stage1_seed"] == 100
        assert config["conditional_seeds"] == [200, 300]
        assert config["stage1_gates"] == {
            "median_delta_classic_at_least": 0.01,
            "median_delta_capacity_above": 0.0,
            "median_delta_late_concat_above": 0.0,
            "win_fraction_classic_at_least": 0.55,
        }
        assert config["formal_evaluation_access"] is False
        assert _sha256(
            REPO_ROOT / "results/26_historical_band_experts/strict_nesting_v06/summary.json"
        ) == config["strict_nesting_summary_sha256"]
        assert _sha256(
            REPO_ROOT / config["legacy_late_concat_predictions"]
        ) == config["legacy_late_concat_predictions_sha256"]

    assert pilot["mode"] == "pilot"
    assert pilot["epochs"] == 30
    assert pilot["limit_batches"] == 0
    assert pilot["limit_validation_samples"] == 0
    assert pilot["results_root"].endswith("sequential_coarse_to_fine_v07")
    assert smoke["mode"] == "smoke"
    assert smoke["epochs"] == 2
    assert smoke["limit_batches"] == 2
    assert smoke["limit_validation_samples"] == 1024
    assert smoke["results_root"].endswith("sequential_coarse_to_fine_v07_smoke")


def test_v07_registry_has_one_preregistered_sequential_transfer_row():
    with (IDEA_ROOT / "registry.csv").open(encoding="utf-8", newline="") as handle:
        rows = [row for row in csv.DictReader(handle) if row["exp_id"] == "E07-S01"]

    assert len(rows) == 1
    assert rows[0]["status"] == "preregistered"
    assert rows[0]["base_config"] == "configs/sequential_transfer_s01_v07.json"
    assert rows[0]["run_dir"].endswith("sequential_coarse_to_fine_v07")


def _dynamic_inputs(batch_size: int = 3) -> tuple[dict[str, torch.Tensor], torch.Tensor]:
    generator = torch.Generator().manual_seed(2707)
    dynamic = {
        "recent": torch.randn(batch_size, 270, 5, generator=generator),
        "medium": torch.randn(batch_size, 60, 5, generator=generator),
        "old": torch.randn(batch_size, 60, 5, generator=generator),
    }
    statics = torch.randn(batch_size, 27, generator=generator)
    return dynamic, statics


def test_v07_sequential_model_shape_structure_count_and_copied_recent_path():
    from models_sequential_v07 import (
        SequentialHistoricalLSTM,
        build_sequential_model_v07,
    )

    classic = build_sequential_model_v07("classic_lstm_256_keyed", seed=100)
    candidate = build_sequential_model_v07("sequential_transfer", seed=100)
    dynamic, statics = _dynamic_inputs()

    assert isinstance(candidate, SequentialHistoricalLSTM)
    assert candidate.old_encoder.input_size == 32
    assert candidate.medium_encoder.input_size == 32
    assert candidate.recent_encoder.input_size == 32
    assert candidate.old_encoder.hidden_size == 256
    assert candidate.medium_encoder.hidden_size == 256
    assert candidate.recent_encoder.hidden_size == 256
    assert all(module.num_layers == 1 for module in candidate.recurrent_modules())
    assert count_trainable_parameters(candidate) == 891_137
    assert sum(isinstance(module, torch.nn.Linear) for module in candidate.modules()) == 1
    assert candidate.recent_encoder.state_dict().keys() == classic.lstm.state_dict().keys()
    for key, value in candidate.recent_encoder.state_dict().items():
        assert torch.equal(value, classic.lstm.state_dict()[key])
    for key, value in candidate.head.state_dict().items():
        assert torch.equal(value, classic.head.state_dict()[key])

    candidate.eval()
    output = candidate(dynamic, statics, dropout_context=None)
    assert output.prediction.shape == (3,)
    assert tuple(output.__dict__) == ("prediction",)


def test_v07_complete_hidden_and_cell_states_flow_old_to_medium_to_recent():
    from models_sequential_v07 import build_sequential_model_v07

    candidate = build_sequential_model_v07("sequential_transfer", seed=100)
    dynamic, statics = _dynamic_inputs(batch_size=2)
    captured: dict[str, tuple[torch.Tensor, torch.Tensor]] = {}

    def save_old(_module, _args, output):
        captured["old_final"] = output[1]

    def save_medium_input(_module, args):
        captured["medium_initial"] = args[1]

    def save_medium(_module, _args, output):
        captured["medium_final"] = output[1]

    def save_recent_input(_module, args):
        captured["recent_initial"] = args[1]

    handles = [
        candidate.old_encoder.register_forward_hook(save_old),
        candidate.medium_encoder.register_forward_pre_hook(save_medium_input),
        candidate.medium_encoder.register_forward_hook(save_medium),
        candidate.recent_encoder.register_forward_pre_hook(save_recent_input),
    ]
    try:
        candidate.eval()
        candidate(dynamic, statics, reset_mode="none")
    finally:
        for handle in handles:
            handle.remove()

    for actual, expected in zip(captured["medium_initial"], captured["old_final"]):
        assert torch.equal(actual, expected)
    for actual, expected in zip(captured["recent_initial"], captured["medium_final"]):
        assert torch.equal(actual, expected)


def test_v07_old_and_medium_inputs_affect_prediction_and_receive_gradients():
    from models_sequential_v07 import build_sequential_model_v07

    candidate = build_sequential_model_v07("sequential_transfer", seed=100)
    dynamic, statics = _dynamic_inputs(batch_size=2)
    candidate.eval()
    reference = candidate(dynamic, statics).prediction
    old_changed = dict(dynamic)
    old_changed["old"] = dynamic["old"] + 1.0
    medium_changed = dict(dynamic)
    medium_changed["medium"] = dynamic["medium"] - 1.0
    assert not torch.equal(candidate(old_changed, statics).prediction, reference)
    assert not torch.equal(candidate(medium_changed, statics).prediction, reference)

    candidate.train()
    candidate(dynamic, statics, dropout_context=(100, 1, 0)).prediction.square().mean().backward()
    for encoder in (
        candidate.old_encoder,
        candidate.medium_encoder,
        candidate.recent_encoder,
    ):
        gradient = encoder.weight_ih_l0.grad
        assert gradient is not None
        assert float(gradient.norm()) > 0


def test_v07_reset_modes_cut_only_the_specified_state_boundaries():
    from models_sequential_v07 import build_sequential_model_v07

    classic = build_sequential_model_v07("classic_lstm_256_keyed", seed=100)
    candidate = build_sequential_model_v07("sequential_transfer", seed=100)
    dynamic, statics = _dynamic_inputs(batch_size=2)
    classic.eval()
    candidate.eval()

    normal = candidate(dynamic, statics, reset_mode="none").prediction
    no_old = candidate(dynamic, statics, reset_mode="old_to_medium").prediction
    no_medium = candidate(dynamic, statics, reset_mode="medium_to_recent").prediction
    recent_only = candidate(dynamic, statics, reset_mode="both").prediction
    classic_prediction = classic(dynamic, statics, dropout_context=None).prediction

    assert not torch.equal(normal, no_old)
    assert not torch.equal(normal, no_medium)
    assert torch.equal(recent_only, classic_prediction)


def _synthetic_pack() -> DataPack:
    periods = default_periods()
    dates = pd.date_range(periods.history_start, periods.validation_end, freq="D")
    generator = np.random.default_rng(727)
    forcing = generator.normal(size=(1, len(dates), 5)).astype(np.float32)
    time = np.arange(len(dates), dtype=np.float32)
    discharge = (
        2.0
        + 0.4 * np.sin(time / 23.0)
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


def _training_config() -> dict:
    config = _load("sequential_transfer_s01_smoke_v07.json")
    config["batch_size"] = 4
    config["validation_batch_size"] = 4
    config["limit_batches"] = 1
    config["limit_validation_samples"] = 8
    return config


def test_v07_dynamic_batches_give_controls_recent_only_and_candidate_all_bands():
    from bands_v03 import forcing_prefix
    from train_sequential_v07 import dynamic_batch_sequential_v07

    forcing = torch.arange(4000 * 5, dtype=torch.float32).reshape(1, 4000, 5)
    prefix = forcing_prefix(forcing)
    basins = torch.tensor([0])
    targets = torch.tensor([3649])

    classic = dynamic_batch_sequential_v07(
        "classic_lstm_256_keyed", forcing, prefix, basins, targets
    )
    candidate = dynamic_batch_sequential_v07(
        "sequential_transfer", forcing, prefix, basins, targets
    )

    assert tuple(classic) == ("recent",)
    assert classic["recent"].shape == (1, 270, 5)
    assert tuple(candidate) == ("recent", "medium", "old")
    assert candidate["recent"].shape == (1, 270, 5)
    assert candidate["medium"].shape == (1, 60, 5)
    assert candidate["old"].shape == (1, 60, 5)


@pytest.mark.parametrize(
    ("key", "value"),
    [
        ("state_transfer", "independent"),
        ("medium_hidden_size", 128),
        ("old_lags", [1826, 3649]),
        ("candidate_parameter_count", 891_138),
        ("dropout_stream", "global"),
        ("formal_evaluation_access", True),
    ],
)
def test_v07_config_rejects_architecture_protocol_or_access_drift(key, value):
    from train_sequential_v07 import validate_sequential_config_v07

    config = _training_config()
    config[key] = value
    with pytest.raises(ValueError, match=key):
        validate_sequential_config_v07(config)


@pytest.mark.parametrize(
    "variant",
    (
        "classic_lstm_256_keyed",
        "classic_lstm_455_keyed",
        "sequential_transfer",
    ),
)
def test_v07_tiny_run_writes_recomputable_artifacts_and_gradient_evidence(tmp_path, variant):
    from train_sequential_v07 import run_sequential_experiment_v07

    output = tmp_path / variant
    manifest = run_sequential_experiment_v07(
        pack=_synthetic_pack(),
        config=_training_config(),
        variant=variant,
        seed=100,
        output_dir=output,
        device="cpu",
    )

    assert manifest["status"] == "complete"
    assert manifest["optimizer_steps_total"] == 2
    assert manifest["n_validation_predictions"] == 8
    assert manifest["data_access"] == {
        "raw_observed_discharge_reads": 0,
        "target_bundle_interface": True,
        "formal_evaluation_access": False,
    }
    assert {path.name for path in output.iterdir()} == {
        "config.json",
        "checkpoint.pt",
        "predictions.csv",
        "per_basin_metrics.csv",
        "state_diagnostics.json",
        "manifest.json",
    }
    predictions = pd.read_csv(output / "predictions.csv", dtype={"basin": str})
    metrics = pd.read_csv(output / "per_basin_metrics.csv", dtype={"basin": str})
    pd.testing.assert_frame_equal(metrics, per_basin_nse(predictions), check_exact=True)
    diagnostics = json.loads((output / "state_diagnostics.json").read_text(encoding="utf-8"))
    if variant == "sequential_transfer":
        assert diagnostics["gradient_reach"]["old_encoder"] > 0
        assert diagnostics["gradient_reach"]["medium_encoder"] > 0
        assert diagnostics["gradient_reach"]["recent_encoder"] > 0
        assert diagnostics["state_transfer"] == "old_to_medium_to_recent_hidden_and_cell"
    else:
        assert diagnostics["state_transfer"] == "not_applicable_recent_only"
    for name, expected in manifest["artifacts"].items():
        assert _sha256(output / name) == expected

    with pytest.raises(FileExistsError, match="not empty"):
        run_sequential_experiment_v07(
            pack=_synthetic_pack(),
            config=_training_config(),
            variant=variant,
            seed=100,
            output_dir=output,
            device="cpu",
        )
