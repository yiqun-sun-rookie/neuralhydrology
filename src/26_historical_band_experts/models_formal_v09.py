"""Clean classic, capacity, strict-nest, and continuous-history models for version 09."""
from __future__ import annotations

import torch
from torch import nn

from models_continuous_v08 import ContinuousMultiscaleHistoryLSTM
from models_equal_experts_v06 import KeyedClassicLSTM


VARIANTS_FORMAL_V09 = (
    "classic_lstm_256_clean",
    "classic_lstm_369_capacity",
    "nested_history_disabled",
    "continuous_multiscale_history",
)
_EXPECTED_TRAINABLE_COUNTS = {
    "classic_lstm_256_clean": 297_217,
    "classic_lstm_369_capacity": 595_198,
    "nested_history_disabled": 297_217,
    "continuous_multiscale_history": 596_737,
}


def _trainable_parameter_count(model: nn.Module) -> int:
    return sum(parameter.numel() for parameter in model.parameters() if parameter.requires_grad)


def build_model_v09(variant: str, seed: int) -> nn.Module:
    """Build one frozen version 09 model without advancing RNG for inert history."""
    if variant not in VARIANTS_FORMAL_V09:
        raise ValueError(f"unknown formal version 09 variant: {variant}")
    torch.manual_seed(int(seed))
    if variant == "classic_lstm_256_clean":
        model = KeyedClassicLSTM(hidden_size=256)
    elif variant == "classic_lstm_369_capacity":
        model = KeyedClassicLSTM(hidden_size=369)
    else:
        model = ContinuousMultiscaleHistoryLSTM(
            history_enabled=variant == "continuous_multiscale_history",
        )
    actual = _trainable_parameter_count(model)
    if actual != _EXPECTED_TRAINABLE_COUNTS[variant]:
        raise RuntimeError(
            f"formal version 09 parameter count drift for {variant}: "
            f"{actual} != {_EXPECTED_TRAINABLE_COUNTS[variant]}"
        )
    return model
