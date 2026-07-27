"""Chronological old-to-medium-to-recent recurrent state transfer."""
from __future__ import annotations

from typing import Mapping

import torch
from torch import nn

from models_equal_experts_v06 import KeyedClassicLSTM, keyed_dropout
from models_v03 import ModelOutput, _append_statics, _set_forget_bias


VARIANTS_SEQUENTIAL_V07 = (
    "classic_lstm_256_keyed",
    "classic_lstm_455_keyed",
    "sequential_transfer",
)
RESET_MODES_SEQUENTIAL_V07 = (
    "none",
    "old_to_medium",
    "medium_to_recent",
    "both",
)


def _zero_state_like(
    state: tuple[torch.Tensor, torch.Tensor],
) -> tuple[torch.Tensor, torch.Tensor]:
    return torch.zeros_like(state[0]), torch.zeros_like(state[1])


class SequentialHistoricalLSTM(nn.Module):
    """Pass complete recurrent state through old, medium, and recent encoders."""

    consumed_dynamic_keys = ("recent", "medium", "old")

    def __init__(
        self,
        dynamic_size: int = 5,
        static_size: int = 27,
        hidden_size: int = 256,
        dropout: float = 0.4,
        forget_bias: float = 5.0,
    ) -> None:
        super().__init__()
        input_size = dynamic_size + static_size
        self.old_encoder = nn.LSTM(input_size, hidden_size, batch_first=True)
        self.medium_encoder = nn.LSTM(input_size, hidden_size, batch_first=True)
        self.recent_encoder = nn.LSTM(input_size, hidden_size, batch_first=True)
        self.head = nn.Linear(hidden_size, 1)
        self.dropout_probability = float(dropout)
        for recurrent in self.recurrent_modules():
            _set_forget_bias(recurrent, forget_bias)

    def recurrent_modules(self) -> tuple[nn.LSTM, ...]:
        return (self.old_encoder, self.medium_encoder, self.recent_encoder)

    def copy_recent_state(self, classic: KeyedClassicLSTM) -> None:
        self.recent_encoder.load_state_dict(classic.lstm.state_dict())
        self.head.load_state_dict(classic.head.state_dict())

    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
        dropout_context: tuple[int, int, int] | None = None,
        reset_mode: str = "none",
    ) -> ModelOutput:
        if reset_mode not in RESET_MODES_SEQUENTIAL_V07:
            raise ValueError(f"unknown reset mode: {reset_mode}")
        _, old_state = self.old_encoder(_append_statics(dynamic["old"], statics))
        medium_initial = (
            _zero_state_like(old_state)
            if reset_mode in ("old_to_medium", "both")
            else old_state
        )
        _, medium_state = self.medium_encoder(
            _append_statics(dynamic["medium"], statics),
            medium_initial,
        )
        recent_initial = (
            _zero_state_like(medium_state)
            if reset_mode in ("medium_to_recent", "both")
            else medium_state
        )
        recent, _ = self.recent_encoder(
            _append_statics(dynamic["recent"], statics),
            recent_initial,
        )
        state = keyed_dropout(
            recent[:, -1],
            probability=self.dropout_probability,
            context=dropout_context,
            branch="recent",
            training=self.training,
        )
        return ModelOutput(prediction=self.head(state)[:, 0])


def build_sequential_model_v07(variant: str, seed: int) -> nn.Module:
    """Build a control or sequential candidate from a common recent initialization."""
    if variant not in VARIANTS_SEQUENTIAL_V07:
        raise ValueError(f"unknown sequential version 07 variant: {variant}")
    torch.manual_seed(int(seed))
    if variant == "classic_lstm_256_keyed":
        return KeyedClassicLSTM(hidden_size=256)
    if variant == "classic_lstm_455_keyed":
        return KeyedClassicLSTM(hidden_size=455)

    classic = KeyedClassicLSTM(hidden_size=256)
    candidate = SequentialHistoricalLSTM()
    candidate.copy_recent_state(classic)
    return candidate
