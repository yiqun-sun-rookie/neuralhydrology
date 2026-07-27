from pathlib import Path
import sys

import pytest
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from models_v03 import ClassicLSTM, count_trainable_parameters
from models_v06 import StrictRecentNestedControl, build_strict_pair_v06


def _inputs(
    device: str = "cpu",
    batch_size: int = 4,
) -> tuple[dict[str, torch.Tensor], torch.Tensor]:
    generator = torch.Generator().manual_seed(606)
    dynamic = {
        "recent": torch.randn(batch_size, 270, 5, generator=generator).to(device),
    }
    statics = torch.randn(batch_size, 27, generator=generator).to(device)
    return dynamic, statics


def _active_named_parameters(model: torch.nn.Module) -> list[tuple[str, torch.nn.Parameter]]:
    return [(name, parameter) for name, parameter in model.named_parameters() if parameter.requires_grad]


def test_v06_nested_control_active_parameters_exactly_match_classic_order_shape_and_values():
    classic, nested = build_strict_pair_v06(seed=100)
    classic_active = _active_named_parameters(classic)
    nested_active = _active_named_parameters(nested)

    assert count_trainable_parameters(classic) == 297_217
    assert count_trainable_parameters(nested) == 297_217
    assert [name for name, _ in nested_active] == [name for name, _ in classic_active]
    assert [tuple(parameter.shape) for _, parameter in nested_active] == [
        tuple(parameter.shape) for _, parameter in classic_active
    ]
    for (_, classic_parameter), (_, nested_parameter) in zip(classic_active, nested_active):
        assert torch.equal(classic_parameter, nested_parameter)


def test_v06_nested_construction_preserves_post_classic_cpu_random_state():
    torch.manual_seed(100)
    ClassicLSTM(hidden_size=256)
    expected_state = torch.get_rng_state().clone()

    _classic, _nested = build_strict_pair_v06(seed=100)

    assert torch.equal(torch.get_rng_state(), expected_state)


def test_v06_nested_control_requires_only_recent_input_and_freezes_all_history_parameters():
    _classic, nested = build_strict_pair_v06(seed=100)
    dynamic, statics = _inputs()

    assert isinstance(nested, StrictRecentNestedControl)
    assert nested.consumed_dynamic_keys == ("recent",)
    assert nested(dynamic, statics).prediction.shape == (4,)
    history_parameters = [
        parameter
        for name, parameter in nested.named_parameters()
        if name.startswith("inert_history.")
    ]
    assert history_parameters
    assert all(not parameter.requires_grad for parameter in history_parameters)


def test_v06_cpu_train_forward_and_random_state_are_bitwise_equal_when_state_is_restored():
    classic, nested = build_strict_pair_v06(seed=100)
    dynamic, statics = _inputs()
    classic.train()
    nested.train()
    initial_state = torch.get_rng_state().clone()

    classic_prediction = classic(dynamic, statics).prediction
    classic_after = torch.get_rng_state().clone()
    torch.set_rng_state(initial_state)
    nested_prediction = nested(dynamic, statics).prediction
    nested_after = torch.get_rng_state().clone()

    assert torch.equal(classic_prediction, nested_prediction)
    assert torch.equal(classic_after, nested_after)


@pytest.mark.skipif(not torch.cuda.is_available(), reason="CUDA is required")
def test_v06_cuda_train_forward_and_random_state_are_bitwise_equal_when_state_is_restored():
    classic, nested = build_strict_pair_v06(seed=100)
    classic = classic.cuda().train()
    nested = nested.cuda().train()
    dynamic, statics = _inputs(device="cuda")
    torch.cuda.manual_seed(1606)
    initial_state = torch.cuda.get_rng_state().clone()

    classic_prediction = classic(dynamic, statics).prediction
    classic_after = torch.cuda.get_rng_state().clone()
    torch.cuda.set_rng_state(initial_state)
    nested_prediction = nested(dynamic, statics).prediction
    nested_after = torch.cuda.get_rng_state().clone()

    assert torch.equal(classic_prediction, nested_prediction)
    assert torch.equal(classic_after, nested_after)
