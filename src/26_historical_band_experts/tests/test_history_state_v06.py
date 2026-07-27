from pathlib import Path
import hashlib
import json
import sys

import numpy as np
import pandas as pd
import pytest
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from data import DataPack, compute_scaler, default_periods
from metrics import per_basin_nse
from models_equal_experts_v06 import build_equal_experts_model_v06
from models_v03 import count_trainable_parameters
from models_history_state_v06 import build_history_state_candidate_v06
from train_history_state_v06 import (
    run_history_state_experiment_v06,
    train_history_state_step_v06,
    validate_history_state_config_v06,
)


def _dynamic(batch_size: int = 4) -> tuple[dict[str, torch.Tensor], torch.Tensor]:
    generator = torch.Generator().manual_seed(930)
    dynamic = {
        "recent": torch.randn(batch_size, 270, 5, generator=generator),
        "medium": torch.randn(batch_size, 60, 5, generator=generator),
        "old": torch.randn(batch_size, 60, 5, generator=generator),
    }
    statics = torch.randn(batch_size, 27, generator=generator)
    return dynamic, statics


def _base_state(seed: int = 100) -> dict[str, torch.Tensor]:
    return build_equal_experts_model_v06(
        "classic_lstm_256_keyed", seed=seed
    ).state_dict()


def _synthetic_pack() -> DataPack:
    periods = default_periods()
    dates = pd.date_range(periods.history_start, periods.validation_end, freq="D")
    generator = np.random.default_rng(934)
    forcing = generator.normal(size=(1, len(dates), 5)).astype(np.float32)
    time = np.arange(len(dates), dtype=np.float32)
    discharge = (
        2.0
        + 0.5 * np.sin(time / 23.0)
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
        "experiment_id": "E06-I03",
        "experiment_family": "frozen_recent_history_state_i03_v06",
        "candidate_iteration": 3,
        "candidate_iteration_budget": 5,
        "mode": "smoke",
        "basin_file_sha256": "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65",
        "target_bundle_sha256": "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c",
        "iteration_two_summary_sha256": "963a945ff555eed629408f7d7857fd893ac509ebe1b47a64cfab0b169d407b54",
        "base_checkpoint_sha256": "6dc004ed0580ddf3f6b81a1ce90c706c0e102713795a7a913ff9798d9f85190b",
        "classic_predictions_sha256": "3ec0c449da8dc1e5165e7082da978676f3369ac39b7c3d1c093572def7ed1b4f",
        "capacity_predictions_sha256": "14c1023e23243ba37db488b7d9f5027081b46de4f1008d1525d1f456e720e5b4",
        "late_concat_predictions_sha256": "dc67277dd9302e7fe5985728a87d82178de1029a9f2bab123a3cbe72d5807941",
        "results_root": "results/26_historical_band_experts/history_state_i03_v06_smoke",
        "epochs": 2,
        "batch_size": 4,
        "validation_batch_size": 4,
        "learning_rate_schedule": {"1": 0.001, "12": 0.0005, "22": 0.0001},
        "gradient_clip": 1.0,
        "initial_forget_bias": 5.0,
        "history_state_dropout": 0.4,
        "dropout_stream": "seed_epoch_batch_branch_sha256",
        "recent_training": "frozen",
        "recent_output_dropout": False,
        "history_injection": "initial_hidden_and_cell_diagonal_gates",
        "state_gate_activation": "tanh",
        "state_gate_initialization": "zero",
        "recent_hidden_size": 256,
        "medium_hidden_size": 256,
        "old_hidden_size": 256,
        "recent_lags": [0, 269],
        "medium_lags": [270, 1824],
        "old_lags": [1825, 3649],
        "medium_bins": 60,
        "old_bins": 60,
        "history_statistics": ["mean"],
        "candidate_parameter_count": 892_161,
        "trainable_history_parameter_count": 594_944,
        "stage1_seed": 100,
        "conditional_seeds": [200, 300],
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


def test_v06_history_state_model_has_three_equal_lstm_experts_and_one_output():
    model = build_history_state_candidate_v06(_base_state(), seed=100)
    dynamic, statics = _dynamic()

    assert model.recent_encoder.input_size == 32
    assert model.medium_encoder.input_size == 32
    assert model.old_encoder.input_size == 32
    assert model.recent_encoder.hidden_size == 256
    assert model.medium_encoder.hidden_size == 256
    assert model.old_encoder.hidden_size == 256
    assert model.recent_encoder.num_layers == 1
    assert model.medium_encoder.num_layers == 1
    assert model.old_encoder.num_layers == 1
    assert sum(parameter.numel() for parameter in model.parameters()) == 892_161
    assert count_trainable_parameters(model) == 594_944
    assert model(dynamic, statics, dropout_context=(100, 1, 0)).prediction.shape == (4,)


def test_v06_zero_state_gates_exactly_reproduce_frozen_classic_prediction():
    dynamic, statics = _dynamic()
    base = build_equal_experts_model_v06("classic_lstm_256_keyed", seed=100)
    candidate = build_history_state_candidate_v06(_base_state(), seed=100)
    base.eval()
    candidate.eval()

    assert torch.equal(
        candidate(dynamic, statics, dropout_context=None).prediction,
        base(dynamic, statics, dropout_context=None).prediction,
    )
    for name, parameter in candidate.named_parameters():
        if name.endswith("_gate"):
            assert torch.count_nonzero(parameter) == 0


def test_v06_history_state_step_changes_history_but_not_recent_parameters():
    dynamic, statics = _dynamic()
    candidate = build_history_state_candidate_v06(_base_state(), seed=100)
    optimizer = torch.optim.Adam(
        (parameter for parameter in candidate.parameters() if parameter.requires_grad),
        lr=0.001,
    )
    before = {name: value.detach().clone() for name, value in candidate.state_dict().items()}
    target = torch.randn(4, generator=torch.Generator().manual_seed(938))

    loss = train_history_state_step_v06(
        model=candidate,
        optimizer=optimizer,
        dynamic=dynamic,
        statics=statics,
        target=target,
        loss_weights=torch.ones(4),
        dropout_context=(100, 1, 0),
        gradient_clip=1.0,
    )

    assert np.isfinite(loss)
    after = candidate.state_dict()
    for name in before:
        if name.startswith(("recent_encoder.", "recent_head.")):
            assert torch.equal(after[name], before[name]), name
    assert any(
        not torch.equal(after[name], before[name])
        for name in before
        if name.endswith("_gate")
    )


def test_v06_tiny_history_state_run_is_recomputable_and_preserves_recent(tmp_path):
    pack = _synthetic_pack()
    scaler = compute_scaler(pack.forcing, pack.discharge, pack.statics, pack.dates)
    base_checkpoint = {
        "model_state_dict": _base_state(),
        "variant": "classic_lstm_256_keyed",
        "seed": 100,
        "parameter_count": 297_217,
        "scaler": scaler,
    }

    manifest = run_history_state_experiment_v06(
        pack=pack,
        config=_config(),
        seed=100,
        base_checkpoint=base_checkpoint,
        output_dir=tmp_path / "candidate",
        device="cpu",
    )

    assert manifest["status"] == "complete"
    assert manifest["optimizer_steps_total"] == 2
    assert manifest["n_validation_predictions"] == 8
    assert manifest["frozen_recent_state_sha256_before"] == (
        manifest["frozen_recent_state_sha256_after"]
    )
    output = tmp_path / "candidate"
    predictions = pd.read_csv(output / "predictions.csv", dtype={"basin": str})
    metrics = pd.read_csv(output / "per_basin_metrics.csv", dtype={"basin": str})
    pd.testing.assert_frame_equal(metrics, per_basin_nse(predictions), check_exact=True)
    for name, expected in manifest["artifacts"].items():
        assert _sha256(output / name) == expected


def test_v06_real_history_state_config_is_valid_and_frozen_inputs_match():
    idea = Path(__file__).resolve().parents[1]
    repo = idea.parents[1]
    config = json.loads(
        (idea / "configs/history_state_i03_v06.json").read_text(encoding="utf-8")
    )
    smoke = json.loads(
        (idea / "configs/history_state_i03_smoke_v06.json").read_text(encoding="utf-8")
    )

    validate_history_state_config_v06(config)
    validate_history_state_config_v06(smoke)
    for path_key, hash_key in (
        ("iteration_two_summary", "iteration_two_summary_sha256"),
        ("base_checkpoint", "base_checkpoint_sha256"),
        ("classic_predictions", "classic_predictions_sha256"),
        ("capacity_predictions", "capacity_predictions_sha256"),
        ("late_concat_predictions", "late_concat_predictions_sha256"),
    ):
        assert _sha256(repo / config[path_key]) == config[hash_key]


@pytest.mark.parametrize(
    ("key", "value"),
    [
        ("candidate_iteration", 2),
        ("recent_training", "joint"),
        ("recent_output_dropout", True),
        ("history_injection", "output_residual"),
        ("state_gate_activation", "sigmoid"),
        ("state_gate_initialization", "random"),
        ("candidate_parameter_count", 892_160),
        ("trainable_history_parameter_count", 594_943),
        ("formal_evaluation_access", True),
    ],
)
def test_v06_history_state_config_rejects_protocol_drift(key, value):
    config = _config()
    config[key] = value
    with pytest.raises(ValueError, match=key):
        validate_history_state_config_v06(config)
