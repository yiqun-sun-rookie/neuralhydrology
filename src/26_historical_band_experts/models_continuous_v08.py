"""Zero-gated continuous multiscale historical state initialization."""
from __future__ import annotations

from typing import Mapping

import torch
from torch import nn

from models_equal_experts_v06 import KeyedClassicLSTM, keyed_dropout
from models_v03 import ModelOutput, _append_statics, _set_forget_bias


VARIANTS_CONTINUOUS_V08 = (
    "classic_lstm_256_keyed",
    "classic_lstm_369_keyed",
    "nested_history_disabled",
    "continuous_multiscale_history",
)
HISTORY_MODES_CONTINUOUS_V08 = ("normal", "history_gates_zero")


class ContinuousMultiscaleHistoryLSTM(KeyedClassicLSTM):
    """Initialize an unchanged recent LSTM from one continuous history encoder."""

    def __init__(
        self,
        history_enabled: bool,
        recent_dynamic_size: int = 5,
        history_dynamic_size: int = 7,
        static_size: int = 27,
        hidden_size: int = 256,
        dropout: float = 0.4,
        forget_bias: float = 5.0,
    ) -> None:
        super().__init__(
            hidden_size=hidden_size,
            dynamic_size=recent_dynamic_size,
            static_size=static_size,
            dropout=dropout,
            forget_bias=forget_bias,
        )
        with torch.random.fork_rng(devices=[]):
            self.history_encoder = nn.LSTM(
                history_dynamic_size + static_size,
                hidden_size,
                batch_first=True,
            )
            _set_forget_bias(self.history_encoder, forget_bias)
        self.hidden_gate = nn.Parameter(torch.zeros(1, 1, hidden_size))
        self.cell_gate = nn.Parameter(torch.zeros(1, 1, hidden_size))
        self.history_enabled = bool(history_enabled)
        if self.history_enabled:
            self.consumed_dynamic_keys = ("recent", "history")
        else:
            self.consumed_dynamic_keys = ("recent",)
            for parameter in self.history_encoder.parameters():
                parameter.requires_grad = False
            self.hidden_gate.requires_grad = False
            self.cell_gate.requires_grad = False

    def recurrent_modules(self) -> tuple[nn.LSTM, ...]:
        return (self.lstm, self.history_encoder)

    def _history_initial_state(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
        history_mode: str,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        _, (hidden, cell) = self.history_encoder(
            _append_statics(dynamic["history"], statics)
        )
        if history_mode == "history_gates_zero":
            return torch.zeros_like(hidden), torch.zeros_like(cell)
        return (
            (torch.tanh(self.hidden_gate) * hidden).contiguous(),
            (torch.tanh(self.cell_gate) * cell).contiguous(),
        )

    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
        dropout_context: tuple[int, int, int] | None = None,
        history_mode: str = "normal",
    ) -> ModelOutput:
        if history_mode not in HISTORY_MODES_CONTINUOUS_V08:
            raise ValueError(f"unknown history mode: {history_mode}")
        if not self.history_enabled:
            return super().forward(dynamic, statics, dropout_context=dropout_context)

        initial = self._history_initial_state(dynamic, statics, history_mode)
        recent, _ = self.lstm(
            _append_statics(dynamic["recent"], statics),
            initial,
        )
        dropped = keyed_dropout(
            recent[:, -1],
            probability=self.dropout_probability,
            context=dropout_context,
            branch="recent",
            training=self.training,
        )
        return ModelOutput(prediction=self.head(dropped)[:, 0])


def build_model_v08(variant: str, seed: int) -> nn.Module:
    """Build a version 08 control, exact nest, or continuous-history candidate."""
    if variant not in VARIANTS_CONTINUOUS_V08:
        raise ValueError(f"unknown continuous-history version 08 variant: {variant}")
    torch.manual_seed(int(seed))
    if variant == "classic_lstm_256_keyed":
        return KeyedClassicLSTM(hidden_size=256)
    if variant == "classic_lstm_369_keyed":
        return KeyedClassicLSTM(hidden_size=369)
    return ContinuousMultiscaleHistoryLSTM(
        history_enabled=variant == "continuous_multiscale_history"
    )
