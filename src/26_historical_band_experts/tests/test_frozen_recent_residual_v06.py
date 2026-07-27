from pathlib import Path
import hashlib
import io
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
from analyze_frozen_residual_v06 import (
    _named_nse_v06,
    evaluate_stage1_frozen_residual_v06,
)
from train_frozen_residual_v06 import (
    _align_recent_reference_v06,
    _compare_recent_reference_v06,
    build_frozen_recent_candidate_v06,
    frozen_recent_prediction_v06,
    history_residual_prediction_v06,
    run_frozen_residual_experiment_v06,
    train_frozen_residual_step_v06,
    validate_frozen_residual_config_v06,
)


def _dynamic(batch_size: int = 4) -> tuple[dict[str, torch.Tensor], torch.Tensor]:
    generator = torch.Generator().manual_seed(902)
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
    generator = np.random.default_rng(906)
    forcing = generator.normal(size=(1, len(dates), 5)).astype(np.float32)
    time = np.arange(len(dates), dtype=np.float32)
    discharge = (
        2.0
        + 0.5 * np.sin(time / 19.0)
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
        "experiment_id": "E06-I02",
        "experiment_family": "frozen_recent_residual_i02_v06",
        "candidate_iteration": 2,
        "candidate_iteration_budget": 5,
        "mode": "smoke",
        "basin_file_sha256": "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65",
        "target_bundle_sha256": "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c",
        "iteration_one_summary_sha256": "4f1e0b20de3e53bf70b2e24939edd71874856267e9b69c535bdbd1005b0470eb",
        "base_checkpoint_sha256": "6dc004ed0580ddf3f6b81a1ce90c706c0e102713795a7a913ff9798d9f85190b",
        "classic_predictions_sha256": "3ec0c449da8dc1e5165e7082da978676f3369ac39b7c3d1c093572def7ed1b4f",
        "capacity_predictions_sha256": "14c1023e23243ba37db488b7d9f5027081b46de4f1008d1525d1f456e720e5b4",
        "late_concat_predictions_sha256": "dc67277dd9302e7fe5985728a87d82178de1029a9f2bab123a3cbe72d5807941",
        "results_root": "results/26_historical_band_experts/frozen_recent_residual_i02_v06_smoke",
        "epochs": 2,
        "batch_size": 4,
        "validation_batch_size": 4,
        "learning_rate_schedule": {"1": 0.001, "12": 0.0005, "22": 0.0001},
        "gradient_clip": 1.0,
        "initial_forget_bias": 5.0,
        "output_dropout": 0.4,
        "dropout_stream": "seed_epoch_batch_branch_sha256",
        "recent_training": "frozen",
        "recent_training_dropout": False,
        "reference_text_roundtrip_dtype": "float32",
        "reference_text_roundtrip_exact": True,
        "history_training": "residual",
        "history_head_initialization": "zero",
        "recent_hidden_size": 256,
        "medium_hidden_size": 256,
        "old_hidden_size": 256,
        "recent_lags": [0, 269],
        "medium_lags": [270, 1824],
        "old_lags": [1825, 3649],
        "medium_bins": 60,
        "old_bins": 60,
        "history_statistics": ["mean"],
        "candidate_parameter_count": 891_649,
        "trainable_history_parameter_count": 594_432,
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


def test_v06_frozen_recent_candidate_starts_exactly_at_base_prediction():
    dynamic, statics = _dynamic()
    base = build_equal_experts_model_v06("classic_lstm_256_keyed", seed=100)
    candidate = build_frozen_recent_candidate_v06(_base_state(), seed=100)
    base.eval()
    candidate.eval()

    expected = base(dynamic, statics).prediction
    recent = frozen_recent_prediction_v06(candidate, dynamic, statics)
    residual = history_residual_prediction_v06(
        candidate, dynamic, statics, dropout_context=None
    )

    assert torch.equal(recent, expected)
    assert torch.count_nonzero(residual) == 0
    assert count_trainable_parameters(candidate) == 594_432


def test_v06_one_residual_step_changes_history_but_not_recent_parameters():
    dynamic, statics = _dynamic()
    candidate = build_frozen_recent_candidate_v06(_base_state(), seed=100)
    optimizer = torch.optim.Adam(
        (parameter for parameter in candidate.parameters() if parameter.requires_grad),
        lr=0.001,
    )
    before = {name: value.detach().clone() for name, value in candidate.state_dict().items()}
    target = torch.randn(4, generator=torch.Generator().manual_seed(907))

    loss = train_frozen_residual_step_v06(
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
        if name.startswith(("medium_", "old_"))
    )


def test_v06_tiny_frozen_residual_run_is_recomputable_and_preserves_recent(tmp_path):
    pack = _synthetic_pack()
    scaler = compute_scaler(pack.forcing, pack.discharge, pack.statics, pack.dates)
    base_checkpoint = {
        "model_state_dict": _base_state(),
        "variant": "classic_lstm_256_keyed",
        "seed": 100,
        "parameter_count": 297_217,
        "scaler": scaler,
    }

    manifest = run_frozen_residual_experiment_v06(
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
    assert manifest["data_access"]["formal_evaluation_access"] is False
    output = tmp_path / "candidate"
    predictions = pd.read_csv(output / "predictions.csv", dtype={"basin": str})
    metrics = pd.read_csv(output / "per_basin_metrics.csv", dtype={"basin": str})
    pd.testing.assert_frame_equal(metrics, per_basin_nse(predictions), check_exact=True)
    for name, expected in manifest["artifacts"].items():
        assert _sha256(output / name) == expected


def test_v06_smoke_recent_check_selects_keys_from_full_reference():
    actual = pd.DataFrame({
        "basin": ["a", "b"],
        "date": ["2007-01-01", "2007-01-01"],
        "qobs": [1.0, 2.0],
        "qsim": [1.1, 2.1],
    })
    full_reference = pd.DataFrame({
        "basin": ["a", "a", "b", "b"],
        "date": ["2006-12-31", "2007-01-01", "2006-12-31", "2007-01-01"],
        "qobs": [0.9, 1.0, 1.9, 2.0],
        "qsim": [1.0, 1.1, 2.0, 2.1],
    })

    aligned = _align_recent_reference_v06(actual, full_reference)

    pd.testing.assert_frame_equal(aligned, actual)


def test_v06_recent_reference_check_requires_exact_float32_roundtrip():
    actual = pd.DataFrame({
        "basin": ["a"],
        "date": ["2007-01-01"],
        "qobs": np.asarray([100.12345], dtype=np.float32),
        "qsim": np.asarray([20.12345], dtype=np.float32),
    })
    stream = io.StringIO()
    actual.to_csv(stream, index=False)
    reference = pd.read_csv(io.StringIO(stream.getvalue()), dtype={"basin": str})

    differences = _compare_recent_reference_v06(
        actual,
        reference,
        roundtrip_dtype="float32",
    )

    assert differences["observation_roundtrip_exact"] is True
    assert differences["prediction_roundtrip_exact"] is True
    changed = reference.copy()
    changed.loc[0, "qobs"] = float(np.nextafter(
        actual.loc[0, "qobs"],
        np.float32(np.inf),
        dtype=np.float32,
    ))
    with pytest.raises(ValueError, match="observation.*round-trip"):
        _compare_recent_reference_v06(
            actual,
            changed,
            roundtrip_dtype="float32",
        )


def test_v06_frozen_residual_stage_gate_uses_paired_basin_differences():
    paired = pd.DataFrame({
        "basin": ["a", "b", "c", "d"],
        "nse_classic": [0.50, 0.60, 0.70, 0.80],
        "nse_capacity": [0.50, 0.60, 0.70, 0.80],
        "nse_late_concat": [0.50, 0.60, 0.70, 0.80],
        "nse_candidate": [0.52, 0.62, 0.72, 0.82],
    })

    result = evaluate_stage1_frozen_residual_v06(
        paired,
        _config()["stage1_gates"],
    )

    assert result["passed"] is True
    assert result["median_delta_classic"] == pytest.approx(0.02)
    assert result["median_delta_capacity"] == pytest.approx(0.02)
    assert result["median_delta_late_concat"] == pytest.approx(0.02)
    assert result["win_fraction_classic"] == 1.0


def test_v06_named_nse_drops_repeated_metric_metadata_before_merge():
    predictions = pd.DataFrame({
        "basin": ["a", "a", "b", "b"],
        "date": ["2007-01-01", "2007-01-02"] * 2,
        "qobs": [1.0, 2.0, 2.0, 4.0],
        "qsim": [1.1, 1.9, 2.1, 3.9],
    })

    metrics = _named_nse_v06(predictions, "candidate")

    assert list(metrics.columns) == ["basin", "nse_candidate"]
    assert len(metrics) == 2


def test_v06_real_frozen_residual_configs_are_valid_and_frozen_inputs_match():
    idea = Path(__file__).resolve().parents[1]
    repo = idea.parents[1]
    pilot = json.loads(
        (idea / "configs/frozen_recent_residual_i02_v06.json").read_text(encoding="utf-8")
    )
    smoke = json.loads(
        (idea / "configs/frozen_recent_residual_i02_smoke_v06.json").read_text(encoding="utf-8")
    )

    validate_frozen_residual_config_v06(pilot)
    validate_frozen_residual_config_v06(smoke)
    for path_key, hash_key in (
        ("iteration_one_summary", "iteration_one_summary_sha256"),
        ("base_checkpoint", "base_checkpoint_sha256"),
        ("classic_predictions", "classic_predictions_sha256"),
        ("capacity_predictions", "capacity_predictions_sha256"),
        ("late_concat_predictions", "late_concat_predictions_sha256"),
    ):
        assert _sha256(repo / pilot[path_key]) == pilot[hash_key]


@pytest.mark.parametrize(
    ("key", "value"),
    [
        ("candidate_iteration", 1),
        ("recent_training", "joint"),
        ("recent_training_dropout", True),
        ("reference_text_roundtrip_dtype", "float64"),
        ("reference_text_roundtrip_exact", False),
        ("history_training", "joint"),
        ("history_head_initialization", "random"),
        ("trainable_history_parameter_count", 594_433),
        ("formal_evaluation_access", True),
    ],
)
def test_v06_frozen_residual_config_rejects_protocol_drift(key, value):
    config = _config()
    config[key] = value
    with pytest.raises(ValueError, match=key):
        validate_frozen_residual_config_v06(config)
