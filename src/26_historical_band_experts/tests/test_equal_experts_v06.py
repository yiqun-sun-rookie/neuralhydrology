from pathlib import Path
import hashlib
import json
import sys

import pytest
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from models_equal_experts_v06 import (
    EqualHistoricalExperts,
    VARIANTS_EQUAL_EXPERTS_V06,
    build_equal_experts_model_v06,
    keyed_dropout,
)
from models_v03 import count_trainable_parameters
from train_equal_experts_v06 import validate_equal_config_v06


EXPECTED_PARAMETER_COUNTS = {
    "classic_lstm_256_keyed": 297_217,
    "classic_lstm_455_keyed": 890_436,
    "late_concat_keyed": 308_401,
    "equal_experts": 891_649,
}


def _inputs(batch_size: int = 3):
    generator = torch.Generator().manual_seed(806)
    dynamic = {
        "recent": torch.randn(batch_size, 270, 5, generator=generator),
        "medium": torch.randn(batch_size, 60, 5, generator=generator),
        "old": torch.randn(batch_size, 60, 5, generator=generator),
    }
    statics = torch.randn(batch_size, 27, generator=generator)
    return dynamic, statics


def test_v06_equal_expert_variants_and_parameter_counts_are_frozen():
    assert VARIANTS_EQUAL_EXPERTS_V06 == (
        "classic_lstm_256_keyed",
        "classic_lstm_455_keyed",
        "late_concat_keyed",
        "equal_experts",
    )
    counts = {
        variant: count_trainable_parameters(build_equal_experts_model_v06(variant, seed=100))
        for variant in VARIANTS_EQUAL_EXPERTS_V06
    }
    assert counts == EXPECTED_PARAMETER_COUNTS
    assert abs(counts["equal_experts"] - counts["classic_lstm_455_keyed"]) == 1_213
    assert 1_213 / counts["equal_experts"] < 0.01


def test_v06_three_equal_experts_have_identical_input_hidden_layers_and_one_output():
    model = build_equal_experts_model_v06("equal_experts", seed=100)
    dynamic, statics = _inputs()

    assert isinstance(model, EqualHistoricalExperts)
    assert model.recent_encoder.input_size == 32
    assert model.medium_encoder.input_size == 32
    assert model.old_encoder.input_size == 32
    assert model.recent_encoder.hidden_size == 256
    assert model.medium_encoder.hidden_size == 256
    assert model.old_encoder.hidden_size == 256
    assert model.recent_encoder.num_layers == 1
    assert model.medium_encoder.num_layers == 1
    assert model.old_encoder.num_layers == 1
    output = model(dynamic, statics, dropout_context=(100, 1, 0))
    assert output.prediction.shape == (3,)
    assert tuple(output.__dict__) == ("prediction",)


def test_v06_equal_experts_initially_match_classic_in_eval_and_train_with_same_recent_key():
    dynamic, statics = _inputs()
    classic = build_equal_experts_model_v06("classic_lstm_256_keyed", seed=100)
    candidate = build_equal_experts_model_v06("equal_experts", seed=100)

    classic.eval()
    candidate.eval()
    assert torch.equal(
        classic(dynamic, statics, dropout_context=(100, 1, 0)).prediction,
        candidate(dynamic, statics, dropout_context=(100, 1, 0)).prediction,
    )
    classic.train()
    candidate.train()
    assert torch.equal(
        classic(dynamic, statics, dropout_context=(100, 1, 0)).prediction,
        candidate(dynamic, statics, dropout_context=(100, 1, 0)).prediction,
    )


def test_v06_keyed_dropout_is_exact_for_same_key_and_different_for_different_branch_keys():
    values = torch.ones(8, 256)

    first = keyed_dropout(values, 0.4, context=(100, 3, 17), branch="recent", training=True)
    second = keyed_dropout(values, 0.4, context=(100, 3, 17), branch="recent", training=True)
    old = keyed_dropout(values, 0.4, context=(100, 3, 17), branch="old", training=True)

    assert torch.equal(first, second)
    assert not torch.equal(first, old)


def test_v06_keyed_dropout_requires_seed_epoch_and_batch_context_during_training():
    with pytest.raises(ValueError, match="dropout_context"):
        keyed_dropout(torch.ones(2, 3), 0.4, context=None, branch="recent", training=True)


def test_v06_iteration_one_config_freezes_protocol_gates_and_isolated_output():
    path = Path(__file__).resolve().parents[1] / "configs" / "equal_experts_i01_v06.json"
    config = json.loads(path.read_text(encoding="utf-8"))

    assert config["experiment_id"] == "E06-I01"
    assert config["candidate_iteration"] == 1
    assert config["candidate_iteration_budget"] == 5
    assert config["results_root"].endswith("equal_experts_i01_v06")
    assert config["epochs"] == 30
    assert config["seeds"] == [100, 200, 300]
    assert config["stage1_seed"] == 100
    assert config["stage1_gates"] == {
        "median_delta_classic_at_least": 0.01,
        "median_delta_capacity_above": 0.0,
        "median_delta_late_concat_above": 0.0,
        "win_fraction_classic_at_least": 0.55,
    }
    assert config["formal_evaluation_access"] is False
    repo = Path(__file__).resolve().parents[3]
    strict_summary = repo / "results/26_historical_band_experts/strict_nesting_v06/summary.json"
    legacy_predictions = repo / config["legacy_late_concat_run_dir"] / "predictions.csv"
    assert hashlib.sha256(strict_summary.read_bytes()).hexdigest() == (
        config["strict_nesting_summary_sha256"]
    )
    assert hashlib.sha256(legacy_predictions.read_bytes()).hexdigest() == (
        config["legacy_late_concat_predictions_sha256"]
    )


def test_v06_iteration_one_smoke_config_is_bounded_and_isolated():
    path = Path(__file__).resolve().parents[1] / "configs" / "equal_experts_i01_smoke_v06.json"
    config = json.loads(path.read_text(encoding="utf-8"))

    assert config["mode"] == "smoke"
    assert config["epochs"] == 2
    assert config["limit_batches"] == 2
    assert config["limit_validation_samples"] == 1024
    assert config["results_root"].endswith("equal_experts_i01_v06_smoke")
    validate_equal_config_v06(config)
