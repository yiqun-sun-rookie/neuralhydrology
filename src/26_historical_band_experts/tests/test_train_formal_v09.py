"""Single-run trainer for the 24 formal main trainings (stage S2).

The scientifically load-bearing checks here are the two history-gate facts: while both
gates are exactly zero the history encoder is gradient-dead (elementwise zero), yet the
gates themselves must carry a strictly positive gradient -- otherwise the history path can
never wake up and E09-CONTINUOUS would silently be a second copy of B09-CAPACITY.
"""
from pathlib import Path
import sys

import numpy as np
import pytest
import torch

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

_WINDOW = 3_562
_RECENT = 270


def _inputs(*, basins=2, days=3_600, targets=4):
    from formal_training_data_v09 import FormalTrainingInputsV09

    generator = np.random.default_rng(29_090)
    dates = np.arange(np.datetime64("1990-01-01"), np.datetime64("1990-01-01") + days)
    return FormalTrainingInputsV09.synthetic(
        forcing=np.ascontiguousarray(generator.normal(size=(basins, days, 5)).astype(np.float32)),
        statics=np.ascontiguousarray(generator.normal(size=(basins, 27)).astype(np.float32)),
        targets=np.ascontiguousarray(generator.normal(size=(basins, targets)).astype(np.float32)),
        dates=dates,
        target_dates=dates[-targets:],
    )


def _spec(samples, batch=4, epochs=2):
    from train_strict_formal_v09 import StrictExecutionSpecV09

    import math
    return StrictExecutionSpecV09(
        epochs=epochs,
        batch_size=batch,
        checkpoint_epochs=tuple(range(1, epochs + 1)),
        expected_samples=samples,
        expected_steps_per_epoch=math.ceil(samples / batch),
        formal=False,
    )


def _train(tmp_path, variant, *, seed=100, record_health=True, name="run"):
    from formal_training_data_v09 import ordered_training_keys_v09
    from train_formal_v09 import run_training_v09

    inputs = _inputs()
    samples = len(ordered_training_keys_v09(inputs)[0])
    return run_training_v09(
        inputs,
        variant=variant,
        seed=seed,
        output_dir=tmp_path / name,
        device="cpu",
        execution_spec=_spec(samples),
        record_health=record_health,
    )


# --------------------------------------------------------------------------------------
# contract
# --------------------------------------------------------------------------------------


@pytest.mark.parametrize("variant, expected", [
    ("classic_lstm_256_clean", 297_217),
    ("classic_lstm_369_capacity", 595_198),
    ("continuous_multiscale_history", 596_737),
])
def test_each_family_trains_with_its_frozen_parameter_count(tmp_path, variant, expected):
    manifest = _train(tmp_path, variant)
    assert manifest["status"] == "formal_training_complete"
    assert manifest["variant"] == variant
    assert manifest["trainable_parameters"] == expected
    assert manifest["validation_metrics_computed"] is False
    assert manifest["formal_evaluation_observation_reads"] == 0
    assert manifest["formal_period_predictions_generated"] is False


def test_the_strict_nesting_control_variant_is_not_a_main_run(tmp_path):
    from train_formal_v09 import run_training_v09

    with pytest.raises(ValueError, match="variant"):
        run_training_v09(
            _inputs(),
            variant="nested_history_disabled",
            seed=100,
            output_dir=tmp_path / "x",
            device="cpu",
            execution_spec=_spec(8),
        )


def test_refuses_to_write_into_an_existing_directory(tmp_path):
    from train_formal_v09 import run_training_v09

    (tmp_path / "taken").mkdir()
    with pytest.raises(FileExistsError, match="already exists"):
        run_training_v09(
            _inputs(),
            variant="classic_lstm_256_clean",
            seed=100,
            output_dir=tmp_path / "taken",
            device="cpu",
            execution_spec=_spec(8),
        )


def test_run_is_sealed_with_checkpoints_and_manifest(tmp_path):
    manifest = _train(tmp_path, "classic_lstm_256_clean")
    run = tmp_path / "run"
    import json
    seal = json.loads((run / "seal.json").read_text(encoding="utf-8"))
    assert seal["status"] == "sealed"
    names = {item["relative_path"] for item in seal["sealed_files"]}
    assert "manifest.json" in names
    assert set(manifest["checkpoint_files"]) <= names


# --------------------------------------------------------------------------------------
# the two history-gate facts
# --------------------------------------------------------------------------------------


def test_history_encoder_is_gradient_dead_while_the_gates_are_zero(tmp_path):
    manifest = _train(tmp_path, "continuous_multiscale_history")
    first = manifest["history_health_trace"][0]
    assert first["step"] == 1
    assert first["gate_absolute_maximum"] == 0.0
    assert first["history_encoder_gradient_norm"] == 0.0
    assert first["gate_gradient_norm"] > 0.0
    assert first["gate_gradients_present"] and first["history_encoder_gradients_present"]


def test_history_encoder_wakes_up_within_three_steps(tmp_path):
    manifest = _train(tmp_path, "continuous_multiscale_history")
    awake = manifest["history_encoder_first_nonzero_gradient_step"]
    assert awake is not None and 1 < awake <= 3


def test_recent_only_families_record_no_history_health(tmp_path):
    manifest = _train(tmp_path, "classic_lstm_256_clean")
    assert manifest["history_health_trace"] == []
    assert manifest["history_encoder_first_nonzero_gradient_step"] is None


def test_gate_health_rejects_a_nonzero_gate_at_the_first_update():
    from train_formal_v09 import FormalTrainingError, _assert_history_health_v09

    health = {
        "step": 1,
        "gate_absolute_maximum": 0.01,
        "gate_gradient_norm": 1.0,
        "history_encoder_gradient_norm": 0.0,
        "gate_gradients_present": True,
        "history_encoder_gradients_present": True,
    }
    with pytest.raises(FormalTrainingError, match="exactly zero"):
        _assert_history_health_v09(health)


def test_gate_health_rejects_a_dead_gate_gradient():
    from train_formal_v09 import FormalTrainingError, _assert_history_health_v09

    health = {
        "step": 1,
        "gate_absolute_maximum": 0.0,
        "gate_gradient_norm": 0.0,
        "history_encoder_gradient_norm": 0.0,
        "gate_gradients_present": True,
        "history_encoder_gradients_present": True,
    }
    with pytest.raises(FormalTrainingError, match="strictly positive"):
        _assert_history_health_v09(health)


def test_gate_health_rejects_a_leaking_history_encoder_gradient():
    from train_formal_v09 import FormalTrainingError, _assert_history_health_v09

    health = {
        "step": 1,
        "gate_absolute_maximum": 0.0,
        "gate_gradient_norm": 1.0,
        "history_encoder_gradient_norm": 1e-9,
        "gate_gradients_present": True,
        "history_encoder_gradients_present": True,
    }
    with pytest.raises(FormalTrainingError, match="exactly zero"):
        _assert_history_health_v09(health)


# --------------------------------------------------------------------------------------
# recording must be pure observation
# --------------------------------------------------------------------------------------


def test_recording_health_changes_nothing_numerically(tmp_path):
    recorded = _train(tmp_path, "continuous_multiscale_history", record_health=True, name="on")
    plain = _train(tmp_path, "continuous_multiscale_history", record_health=False, name="off")
    for key in ("epoch_trace", "trainable_parameters", "optimizer_steps_total", "dropout_rng_binding"):
        assert recorded[key] == plain[key], key
    checkpoint = "checkpoint_epoch001.pt"
    a = torch.load(tmp_path / "on" / checkpoint, map_location="cpu", weights_only=False)
    b = torch.load(tmp_path / "off" / checkpoint, map_location="cpu", weights_only=False)
    for name, tensor in a["model_state_dict"].items():
        assert torch.equal(tensor, b["model_state_dict"][name]), name


# --------------------------------------------------------------------------------------
# the three families of one seed must stay comparable
# --------------------------------------------------------------------------------------


def test_all_three_families_of_one_seed_share_every_epoch_permutation(tmp_path):
    hashes = {}
    for variant in ("classic_lstm_256_clean", "classic_lstm_369_capacity", "continuous_multiscale_history"):
        manifest = _train(tmp_path, variant, seed=300, name=variant)
        hashes[variant] = [row["permutation_sha256"] for row in manifest["epoch_trace"]]
    values = list(hashes.values())
    assert values[0] == values[1] == values[2]


def test_all_three_families_of_one_seed_share_the_dropout_binding(tmp_path):
    bindings = set()
    for variant in ("classic_lstm_256_clean", "classic_lstm_369_capacity", "continuous_multiscale_history"):
        manifest = _train(tmp_path, variant, seed=500, name=variant)
        bindings.add(manifest["dropout_rng_binding"]["cpu_state_sha256"])
    assert len(bindings) == 1


def test_different_seeds_use_different_permutations(tmp_path):
    a = _train(tmp_path, "classic_lstm_256_clean", seed=100, name="a")
    b = _train(tmp_path, "classic_lstm_256_clean", seed=200, name="b")
    assert a["epoch_trace"][0]["permutation_sha256"] != b["epoch_trace"][0]["permutation_sha256"]


def test_non_finite_loss_stops_the_step():
    from train_formal_v09 import FormalTrainingError, single_train_step_v09
    from models_formal_v09 import build_model_v09

    model = build_model_v09("classic_lstm_256_clean", 100)
    optimizer = torch.optim.Adam(model.parameters(), lr=0.001)
    dynamic = {"recent": torch.zeros(2, _RECENT, 5)}
    statics = torch.zeros(2, 27)
    target = torch.tensor([float("nan"), 0.0])
    weights = torch.ones(2)
    with pytest.raises(FormalTrainingError, match="non-finite"):
        single_train_step_v09(
            model, optimizer, dynamic, statics, target, weights,
            dropout_context=(100, 1, 0), gradient_clip=1.0, step_index=1,
        )
