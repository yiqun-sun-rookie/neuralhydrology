from pathlib import Path
import sys

import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from models_v03 import (
    ClassicLSTM,
    InitialMemoryHistoricalLSTM,
    LateConcatHistoricalLSTM,
    build_model_v03,
    count_trainable_parameters,
)


EXPECTED_PARAMETERS = {
    "classic_lstm_256": 297_217,
    "classic_lstm_261": 308_242,
    "classic_lstm_266": 319_467,
    "late_concat": 308_401,
    "initial_memory": 320_897,
}


def _inputs(batch_size: int = 4) -> tuple[dict[str, torch.Tensor], torch.Tensor]:
    generator = torch.Generator().manual_seed(23)
    dynamic = {
        "recent": torch.randn(batch_size, 270, 5, generator=generator),
        "medium": torch.randn(batch_size, 60, 5, generator=generator),
        "old": torch.randn(batch_size, 60, 5, generator=generator),
    }
    statics = torch.randn(batch_size, 27, generator=generator)
    return dynamic, statics


def test_v03_parameter_counts_match_frozen_design():
    for variant, expected in EXPECTED_PARAMETERS.items():
        model = build_model_v03(variant, seed=100)
        assert count_trainable_parameters(model) == expected

    late_gap = abs(EXPECTED_PARAMETERS["late_concat"] - EXPECTED_PARAMETERS["classic_lstm_261"])
    memory_gap = abs(EXPECTED_PARAMETERS["initial_memory"] - EXPECTED_PARAMETERS["classic_lstm_266"])
    assert late_gap / EXPECTED_PARAMETERS["late_concat"] < 0.01
    assert memory_gap / EXPECTED_PARAMETERS["initial_memory"] < 0.01


def test_v03_every_recurrent_module_has_forget_bias_five():
    for variant in EXPECTED_PARAMETERS:
        model = build_model_v03(variant, seed=100)
        for recurrent in model.recurrent_modules():
            hidden_size = recurrent.hidden_size
            torch.testing.assert_close(
                recurrent.bias_hh_l0[hidden_size:2 * hidden_size],
                torch.full((hidden_size,), 5.0),
            )


def test_v03_all_arms_return_one_flow_only():
    dynamic, statics = _inputs()
    for variant in EXPECTED_PARAMETERS:
        model = build_model_v03(variant, seed=100)
        output = model(dynamic, statics)
        assert output.prediction.shape == (4,)
        assert tuple(output.__dict__) == ("prediction",)


def test_v03_classic_controls_use_only_recent_input():
    dynamic, statics = _inputs()
    for variant in ("classic_lstm_256", "classic_lstm_261", "classic_lstm_266"):
        model = build_model_v03(variant, seed=100).eval()
        reference = model(dynamic, statics).prediction
        changed = dict(dynamic)
        changed["medium"] = torch.full_like(dynamic["medium"], 1_000_000.0)
        changed["old"] = torch.full_like(dynamic["old"], -1_000_000.0)
        torch.testing.assert_close(reference, model(changed, statics).prediction)


def test_v03_candidates_initially_equal_same_classic_reference_in_eval_mode():
    dynamic, statics = _inputs()
    classic = build_model_v03("classic_lstm_256", seed=100).eval()
    reference = classic(dynamic, statics).prediction

    for variant in ("late_concat", "initial_memory"):
        candidate = build_model_v03(variant, seed=100).eval()
        torch.testing.assert_close(candidate(dynamic, statics).prediction, reference, rtol=0, atol=0)


def test_v03_late_concat_historical_encoders_receive_gradient_after_connector_update():
    dynamic, statics = _inputs()
    model = build_model_v03("late_concat", seed=100)
    assert isinstance(model, LateConcatHistoricalLSTM)
    optimizer = torch.optim.SGD(model.parameters(), lr=0.01)

    model(dynamic, statics).prediction.square().mean().backward()
    optimizer.step()
    optimizer.zero_grad()
    model(dynamic, statics).prediction.square().mean().backward()

    assert model.medium_encoder.weight_ih_l0.grad.abs().sum() > 0
    assert model.old_encoder.weight_ih_l0.grad.abs().sum() > 0


def test_v03_initial_memory_historical_encoders_receive_gradient_after_connector_update():
    dynamic, statics = _inputs()
    model = build_model_v03("initial_memory", seed=100)
    assert isinstance(model, InitialMemoryHistoricalLSTM)
    optimizer = torch.optim.SGD(model.parameters(), lr=0.01)

    model(dynamic, statics).prediction.square().mean().backward()
    optimizer.step()
    optimizer.zero_grad()
    model(dynamic, statics).prediction.square().mean().backward()

    assert model.medium_encoder.weight_ih_l0.grad.abs().sum() > 0
    assert model.old_encoder.weight_ih_l0.grad.abs().sum() > 0


def test_v03_model_factory_rejects_unknown_variant():
    try:
        build_model_v03("not_a_model", seed=100)
    except ValueError as error:
        assert "unknown variant" in str(error)
    else:
        raise AssertionError("unknown variant was accepted")


def test_v03_public_classes_have_expected_widths():
    assert ClassicLSTM().lstm.hidden_size == 256
    assert LateConcatHistoricalLSTM().medium_encoder.hidden_size == 24
    assert InitialMemoryHistoricalLSTM().history_to_cell.out_features == 256
