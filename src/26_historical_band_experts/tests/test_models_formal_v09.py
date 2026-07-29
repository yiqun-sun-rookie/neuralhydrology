from pathlib import Path
import sys

import torch


IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def _dynamic(batch_size: int = 2):
    generator = torch.Generator().manual_seed(2909)
    return {
        "recent": torch.randn(batch_size, 12, 5, generator=generator),
        "history": torch.randn(batch_size, 8, 7, generator=generator),
    }, torch.randn(batch_size, 27, generator=generator)


def test_v09_models_have_frozen_parameter_counts_and_one_output():
    from models_formal_v09 import build_model_v09
    from models_v03 import count_trainable_parameters

    classic = build_model_v09("classic_lstm_256_clean", 100)
    capacity = build_model_v09("classic_lstm_369_capacity", 100)
    candidate = build_model_v09("continuous_multiscale_history", 100)
    dynamic, statics = _dynamic()

    assert count_trainable_parameters(classic) == 297_217
    assert count_trainable_parameters(capacity) == 595_198
    assert count_trainable_parameters(candidate) == 596_737
    assert candidate.lstm.hidden_size == candidate.history_encoder.hidden_size == 256
    assert candidate.lstm.num_layers == candidate.history_encoder.num_layers == 1
    assert sum(isinstance(module, torch.nn.Linear) for module in candidate.modules()) == 1
    candidate.eval()
    assert candidate(dynamic, statics).prediction.shape == (2,)


def test_v09_candidate_zero_gate_initial_prediction_equals_clean_classic():
    from models_formal_v09 import build_model_v09

    classic = build_model_v09("classic_lstm_256_clean", 100)
    candidate = build_model_v09("continuous_multiscale_history", 100)
    dynamic, statics = _dynamic()

    classic.eval()
    candidate.eval()
    assert torch.count_nonzero(candidate.hidden_gate).item() == 0
    assert torch.count_nonzero(candidate.cell_gate).item() == 0
    assert torch.equal(
        classic({"recent": dynamic["recent"]}, statics).prediction,
        candidate(dynamic, statics).prediction,
    )


def test_v09_disabled_history_is_exact_active_parameter_nest():
    from models_formal_v09 import build_model_v09
    from train_strict_v06 import active_named_parameters

    classic = build_model_v09("classic_lstm_256_clean", 100)
    classic_rng = torch.get_rng_state().clone()
    nested = build_model_v09("nested_history_disabled", 100)
    nested_rng = torch.get_rng_state().clone()

    classic_parameters = active_named_parameters(classic)
    nested_parameters = active_named_parameters(nested)
    assert [name for name, _ in classic_parameters] == [name for name, _ in nested_parameters]
    for (_, reference), (_, candidate) in zip(classic_parameters, nested_parameters):
        assert torch.equal(reference, candidate)
    assert torch.equal(classic_rng, nested_rng)
    assert tuple(nested.consumed_dynamic_keys) == ("recent",)
