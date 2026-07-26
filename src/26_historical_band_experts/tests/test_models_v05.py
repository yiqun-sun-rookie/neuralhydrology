from pathlib import Path
import sys

import pytest
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from models_v05 import _state_from_statics, build_model_v05, count_trainable_parameters


EXPECTED_PARAMETERS = {
    "classic_lstm_256": 297_217,
    "classic_lstm_320": 453_441,
    "hierarchical_rich_history": 455_105,
}


def _inputs(batch_size: int = 4) -> tuple[dict[str, torch.Tensor], torch.Tensor]:
    generator = torch.Generator().manual_seed(61)
    dynamic = {
        "recent": torch.randn(batch_size, 270, 5, generator=generator),
        "medium": torch.randn(batch_size, 60, 20, generator=generator),
        "old": torch.randn(batch_size, 5, 12, 20, generator=generator),
    }
    statics = torch.randn(batch_size, 27, generator=generator)
    return dynamic, statics


def test_v05_parameter_counts_match_frozen_design_and_capacity_gap():
    counts = {
        variant: count_trainable_parameters(build_model_v05(variant, seed=100))
        for variant in EXPECTED_PARAMETERS
    }
    assert counts == EXPECTED_PARAMETERS
    gap = abs(counts["hierarchical_rich_history"] - counts["classic_lstm_320"])
    assert gap == 1_664
    assert gap / counts["hierarchical_rich_history"] < 0.004


def test_v05_all_recurrent_modules_have_forget_bias_five():
    for variant in EXPECTED_PARAMETERS:
        model = build_model_v05(variant, seed=100)
        for recurrent in model.recurrent_modules():
            hidden_size = recurrent.hidden_size
            torch.testing.assert_close(
                recurrent.bias_hh_l0[hidden_size:2 * hidden_size],
                torch.full((hidden_size,), 5.0),
            )


def test_v05_all_arms_return_exactly_one_flow():
    dynamic, statics = _inputs()
    for variant in EXPECTED_PARAMETERS:
        output = build_model_v05(variant, seed=100)(dynamic, statics)
        assert output.prediction.shape == (4,)
        assert tuple(output.__dict__) == ("prediction",)


def test_v05_candidate_initially_equals_same_classic_reference_in_eval_mode():
    dynamic, statics = _inputs()
    classic = build_model_v05("classic_lstm_256", seed=100).eval()
    candidate = build_model_v05("hierarchical_rich_history", seed=100).eval()
    torch.testing.assert_close(
        candidate(dynamic, statics).prediction,
        classic(dynamic, statics).prediction,
        rtol=0,
        atol=0,
    )


def test_v05_classic_controls_use_only_recent_input():
    dynamic, statics = _inputs()
    for variant in ("classic_lstm_256", "classic_lstm_320"):
        model = build_model_v05(variant, seed=100).eval()
        reference = model(dynamic, statics).prediction
        changed = dict(dynamic)
        changed["medium"] = torch.full_like(dynamic["medium"], 1_000_000.0)
        changed["old"] = torch.full_like(dynamic["old"], -1_000_000.0)
        torch.testing.assert_close(reference, model(changed, statics).prediction)


def test_v05_history_static_initializers_change_with_static_attributes():
    model = build_model_v05("hierarchical_rich_history", seed=100)
    first = torch.zeros(3, 27)
    second = torch.ones(3, 27)
    for projection in (
        model.medium_static_state,
        model.old_within_static_state,
        model.old_across_static_state,
    ):
        assert not torch.equal(projection(first), projection(second))


def test_v05_history_encoders_receive_gradient_after_head_update():
    dynamic, statics = _inputs()
    model = build_model_v05("hierarchical_rich_history", seed=100)
    optimizer = torch.optim.SGD(model.parameters(), lr=0.01)

    model(dynamic, statics).prediction.square().mean().backward()
    assert model.medium_encoder.weight_ih_l0.grad.abs().sum() == 0
    assert model.old_within_encoder.weight_ih_l0.grad.abs().sum() == 0
    assert model.old_across_encoder.weight_ih_l0.grad.abs().sum() == 0
    optimizer.step()
    optimizer.zero_grad()

    model(dynamic, statics).prediction.square().mean().backward()
    assert model.medium_encoder.weight_ih_l0.grad.abs().sum() > 0
    assert model.old_within_encoder.weight_ih_l0.grad.abs().sum() > 0
    assert model.old_across_encoder.weight_ih_l0.grad.abs().sum() > 0


def test_v05_model_factory_rejects_unknown_variant():
    with pytest.raises(ValueError, match="unknown variant"):
        build_model_v05("not_a_model", seed=100)

def test_v05_static_initial_states_are_contiguous_for_cuda_recurrent_kernels():
    projection = torch.nn.Linear(27, 128)
    hidden, cell = _state_from_statics(projection, torch.randn(4, 27))
    assert hidden.is_contiguous()
    assert cell.is_contiguous()
