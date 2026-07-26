from pathlib import Path
import sys

import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from models import (
    HistoricalBandExperts,
    MainstreamLSTM,
    MultiscaleFusion,
    count_trainable_parameters,
)


def _inputs(batch_size: int = 4):
    generator = torch.Generator().manual_seed(23)
    dynamic = {
        "mainstream": torch.randn(batch_size, 270, 5, generator=generator),
        "recent": torch.randn(batch_size, 30, 5, generator=generator),
        "medium": torch.randn(batch_size, 60, 5, generator=generator),
        "old": torch.randn(batch_size, 60, 5, generator=generator),
    }
    statics = torch.randn(batch_size, 27, generator=generator)
    return dynamic, statics


def _models():
    return (
        MainstreamLSTM(dynamic_size=5, static_size=27),
        MultiscaleFusion(dynamic_size=5, static_size=27),
        HistoricalBandExperts(dynamic_size=5, static_size=27),
    )


def test_all_model_arms_return_one_prediction_per_sample():
    dynamic, statics = _inputs()
    for model in _models():
        output = model(dynamic, statics)
        assert output.prediction.shape == (4,)
        assert torch.isfinite(output.prediction).all()


def test_expert_weights_are_nonnegative_and_sum_to_one():
    dynamic, statics = _inputs()
    output = HistoricalBandExperts(5, 27)(dynamic, statics)

    assert output.weights is not None
    assert output.weights.shape == (4, 3)
    assert torch.all(output.weights >= 0)
    torch.testing.assert_close(
        output.weights.sum(dim=1),
        torch.ones(4),
        rtol=0,
        atol=1e-6,
    )
    assert output.expert_predictions is not None
    assert output.expert_predictions.shape == (4, 3)


def test_expert_loss_reaches_every_encoder_head_and_gate():
    dynamic, statics = _inputs()
    model = HistoricalBandExperts(5, 27)
    output = model(dynamic, statics)
    output.prediction.square().mean().backward()

    required_modules = (
        model.recent_encoder,
        model.medium_encoder,
        model.old_encoder,
        model.expert_heads,
        model.gate,
    )
    for module in required_modules:
        gradients = [parameter.grad for parameter in module.parameters()]
        assert gradients
        assert all(gradient is not None for gradient in gradients)
        assert sum(float(gradient.abs().sum()) for gradient in gradients) > 0


def test_all_model_arms_have_parameter_counts_within_two_percent():
    counts = [count_trainable_parameters(model) for model in _models()]
    spread = (max(counts) - min(counts)) / max(counts)

    assert spread <= 0.02, counts


def test_multiscale_arms_accept_the_exact_same_dynamic_tensors():
    dynamic, statics = _inputs()
    fusion = MultiscaleFusion(5, 27)
    experts = HistoricalBandExperts(5, 27)

    fusion_output = fusion(dynamic, statics)
    expert_output = experts(dynamic, statics)

    assert fusion_output.prediction.shape == expert_output.prediction.shape
    assert set(fusion.consumed_dynamic_keys) == set(experts.consumed_dynamic_keys)
    assert set(fusion.consumed_dynamic_keys) == {"recent", "medium", "old"}


def test_forget_gate_bias_matches_mainstream_baseline():
    for model in _models():
        for lstm in model.recurrent_modules():
            hidden_size = lstm.hidden_size
            expected = torch.full((hidden_size,), 5.0)
            torch.testing.assert_close(
                lstm.bias_hh_l0[hidden_size:2 * hidden_size],
                expected,
            )

class _RecordingOffsetDropout(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.outputs = []

    def forward(self, value):
        output = value + 100.0
        self.outputs.append(output.detach().clone())
        return output


def test_multiscale_arms_apply_dropout_only_to_the_same_three_encoder_states():
    dynamic, statics = _inputs()
    for model in (MultiscaleFusion(5, 27), HistoricalBandExperts(5, 27)):
        recorder = _RecordingOffsetDropout()
        model.dropout = recorder
        captured = {}
        handles = []
        if isinstance(model, MultiscaleFusion):
            handles.append(model.head[0].register_forward_pre_hook(
                lambda _module, inputs: captured.setdefault("features", inputs[0].detach().clone())
            ))
        else:
            for index, head in enumerate(model.expert_heads):
                handles.append(head.register_forward_pre_hook(
                    lambda _module, inputs, index=index: captured.setdefault(
                        f"head_{index}", inputs[0].detach().clone()
                    )
                ))
            handles.append(model.gate[0].register_forward_pre_hook(
                lambda _module, inputs: captured.setdefault("features", inputs[0].detach().clone())
            ))

        model(dynamic, statics)
        for handle in handles:
            handle.remove()

        assert len(recorder.outputs) == 3
        assert [tuple(value.shape) for value in recorder.outputs] == [(4, 64)] * 3
        features = captured["features"]
        for index, dropped_state in enumerate(recorder.outputs):
            start = index * 64
            torch.testing.assert_close(features[:, start:start + 64], dropped_state)
            if isinstance(model, HistoricalBandExperts):
                torch.testing.assert_close(captured[f"head_{index}"], dropped_state)
        torch.testing.assert_close(features[:, 192:197], dynamic["recent"][:, -1])
        torch.testing.assert_close(features[:, 197:], statics)
