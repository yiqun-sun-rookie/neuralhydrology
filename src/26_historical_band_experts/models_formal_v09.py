"""Core-compatible classic, capacity, strict-nest, and history models for version 09."""
from __future__ import annotations

from typing import Mapping

import torch
from torch import nn

from models_v03 import ModelOutput, _append_statics, _set_forget_bias
from neuralhydrology.modelzoo.head import Regression


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
HISTORY_MODES_FORMAL_V09 = ("normal", "history_gates_zero")


class CoreCompatibleClassicLSTM(nn.Module):
    """Mirror the core CudaLSTM recent path while returning only the final flow."""

    consumed_dynamic_keys = ("recent",)

    def __init__(
        self,
        hidden_size: int,
        dynamic_size: int = 5,
        static_size: int = 27,
        dropout: float = 0.4,
        forget_bias: float = 5.0,
    ) -> None:
        super().__init__()
        self.lstm = nn.LSTM(
            dynamic_size + static_size,
            hidden_size,
            batch_first=True,
        )
        self.dropout = nn.Dropout(float(dropout))
        self.head = Regression(
            n_in=hidden_size,
            n_out=1,
            activation="linear",
        )
        self.dropout_probability = float(dropout)
        _set_forget_bias(self.lstm, forget_bias)

    def recurrent_modules(self) -> tuple[nn.LSTM, ...]:
        return (self.lstm,)

    def _prediction_from_encoded(self, encoded: torch.Tensor) -> torch.Tensor:
        prediction_sequence = self.head(self.dropout(encoded))["y_hat"]
        return prediction_sequence[:, -1, 0]

    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
        dropout_context: tuple[int, int, int] | None = None,
    ) -> ModelOutput:
        del dropout_context
        encoded, _ = self.lstm(_append_statics(dynamic["recent"], statics))
        return ModelOutput(prediction=self._prediction_from_encoded(encoded))


class CoreCompatibleContinuousHistoryLSTM(CoreCompatibleClassicLSTM):
    """Initialize the core-compatible recent path from zero-gated historical state."""

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
        del dropout_context
        if history_mode not in HISTORY_MODES_FORMAL_V09:
            raise ValueError(f"unknown history mode: {history_mode}")
        if not self.history_enabled:
            encoded, _ = self.lstm(_append_statics(dynamic["recent"], statics))
            return ModelOutput(prediction=self._prediction_from_encoded(encoded))
        initial = self._history_initial_state(dynamic, statics, history_mode)
        encoded, _ = self.lstm(
            _append_statics(dynamic["recent"], statics),
            initial,
        )
        return ModelOutput(prediction=self._prediction_from_encoded(encoded))


def _trainable_parameter_count(model: nn.Module) -> int:
    return sum(parameter.numel() for parameter in model.parameters() if parameter.requires_grad)


def build_model_v09(variant: str, seed: int) -> nn.Module:
    """Build one frozen version 09 model without advancing RNG for inert history."""
    if variant not in VARIANTS_FORMAL_V09:
        raise ValueError(f"unknown formal version 09 variant: {variant}")
    torch.manual_seed(int(seed))
    if variant == "classic_lstm_256_clean":
        model = CoreCompatibleClassicLSTM(hidden_size=256)
    elif variant == "classic_lstm_369_capacity":
        model = CoreCompatibleClassicLSTM(hidden_size=369)
    else:
        model = CoreCompatibleContinuousHistoryLSTM(
            history_enabled=variant == "continuous_multiscale_history",
        )
    actual = _trainable_parameter_count(model)
    if actual != _EXPECTED_TRAINABLE_COUNTS[variant]:
        raise RuntimeError(
            f"formal version 09 parameter count drift for {variant}: "
            f"{actual} != {_EXPECTED_TRAINABLE_COUNTS[variant]}"
        )
    return model
