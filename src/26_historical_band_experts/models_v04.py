"""Single-output models for persistent and recent-conditioned historical context."""
from __future__ import annotations

from typing import Mapping

import torch
from torch import nn

from models_v03 import (
    ClassicLSTM,
    LateConcatHistoricalLSTM,
    ModelOutput,
    count_trainable_parameters,
    _append_statics,
    _set_forget_bias,
)


VARIANTS_V04 = (
    "classic_lstm_256",
    "classic_lstm_261",
    "classic_lstm_265",
    "classic_lstm_270",
    "late_concat",
    "persistent_context",
    "recent_conditioned_residual",
)


class PersistentContextLSTM(nn.Module):
    """Expose an eight-dimensional historical context at every recent step."""

    consumed_dynamic_keys = ("recent", "medium", "old")

    def __init__(
        self,
        dynamic_size: int = 5,
        static_size: int = 27,
        recent_hidden_size: int = 256,
        history_hidden_size: int = 24,
        context_size: int = 8,
        dropout: float = 0.4,
    ) -> None:
        super().__init__()
        input_size = dynamic_size + static_size
        self.medium_encoder = nn.LSTM(input_size, history_hidden_size, batch_first=True)
        self.old_encoder = nn.LSTM(input_size, history_hidden_size, batch_first=True)
        self.history_projection = nn.Linear(2 * history_hidden_size, context_size)
        self.lstm = nn.LSTM(input_size + context_size, recent_hidden_size, batch_first=True)
        self.dropout = nn.Dropout(dropout)
        self.head = nn.Linear(recent_hidden_size, 1)
        for recurrent in self.recurrent_modules():
            _set_forget_bias(recurrent, 5.0)

    def recurrent_modules(self) -> tuple[nn.LSTM, ...]:
        return (self.lstm, self.medium_encoder, self.old_encoder)

    def copy_classic_state(self, classic: ClassicLSTM) -> None:
        """Copy the classic backbone and make the added input columns neutral."""
        if self.lstm.hidden_size != classic.lstm.hidden_size:
            raise ValueError("recent hidden size does not match classic reference")
        with torch.no_grad():
            self.lstm.weight_ih_l0.zero_()
            self.lstm.weight_ih_l0[:, :classic.lstm.input_size].copy_(classic.lstm.weight_ih_l0)
            self.lstm.weight_hh_l0.copy_(classic.lstm.weight_hh_l0)
            self.lstm.bias_ih_l0.copy_(classic.lstm.bias_ih_l0)
            self.lstm.bias_hh_l0.copy_(classic.lstm.bias_hh_l0)
        self.head.load_state_dict(classic.head.state_dict())
    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
    ) -> ModelOutput:
        medium, _ = self.medium_encoder(_append_statics(dynamic["medium"], statics))
        old, _ = self.old_encoder(_append_statics(dynamic["old"], statics))
        history = torch.cat((medium[:, -1], old[:, -1]), dim=-1)
        context = self.history_projection(history)
        recent_input = _append_statics(dynamic["recent"], statics)
        repeated_context = context.unsqueeze(1).expand(-1, recent_input.shape[1], -1)
        recent, _ = self.lstm(torch.cat((recent_input, repeated_context), dim=-1))
        prediction = self.head(self.dropout(recent[:, -1]))[:, 0]
        return ModelOutput(prediction=prediction)


class RecentConditionedResidualLSTM(nn.Module):
    """Add a recent-conditioned historical residual before one classic head."""

    consumed_dynamic_keys = ("recent", "medium", "old")

    def __init__(
        self,
        dynamic_size: int = 5,
        static_size: int = 27,
        recent_hidden_size: int = 256,
        history_hidden_size: int = 24,
        residual_size: int = 32,
        dropout: float = 0.4,
    ) -> None:
        super().__init__()
        input_size = dynamic_size + static_size
        self.lstm = nn.LSTM(input_size, recent_hidden_size, batch_first=True)
        self.medium_encoder = nn.LSTM(input_size, history_hidden_size, batch_first=True)
        self.old_encoder = nn.LSTM(input_size, history_hidden_size, batch_first=True)
        self.history_projection = nn.Linear(2 * history_hidden_size, residual_size)
        self.history_gate = nn.Linear(recent_hidden_size + residual_size, residual_size)
        self.residual_projection = nn.Linear(residual_size, recent_hidden_size)
        self.dropout = nn.Dropout(dropout)
        self.head = nn.Linear(recent_hidden_size, 1)
        for recurrent in self.recurrent_modules():
            _set_forget_bias(recurrent, 5.0)

    def recurrent_modules(self) -> tuple[nn.LSTM, ...]:
        return (self.lstm, self.medium_encoder, self.old_encoder)

    def copy_classic_state(self, classic: ClassicLSTM) -> None:
        """Copy the classic model and initialize the historical residual at zero."""
        if self.lstm.hidden_size != classic.lstm.hidden_size:
            raise ValueError("recent hidden size does not match classic reference")
        self.lstm.load_state_dict(classic.lstm.state_dict())
        self.head.load_state_dict(classic.head.state_dict())
        with torch.no_grad():
            self.residual_projection.weight.zero_()
            self.residual_projection.bias.zero_()
    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
    ) -> ModelOutput:
        recent, _ = self.lstm(_append_statics(dynamic["recent"], statics))
        medium, _ = self.medium_encoder(_append_statics(dynamic["medium"], statics))
        old, _ = self.old_encoder(_append_statics(dynamic["old"], statics))
        history = self.history_projection(torch.cat((medium[:, -1], old[:, -1]), dim=-1))
        recent_state = recent[:, -1]
        gate = torch.sigmoid(self.history_gate(torch.cat((recent_state, history), dim=-1)))
        adjusted = recent_state + self.residual_projection(gate * history)
        prediction = self.head(self.dropout(adjusted))[:, 0]
        return ModelOutput(prediction=prediction)


def build_model_v04(variant: str, seed: int) -> nn.Module:
    """Build one deterministic arm, nesting candidates in the same classic seed."""
    if variant not in VARIANTS_V04:
        raise ValueError(f"unknown variant: {variant}")
    torch.manual_seed(int(seed))
    if variant.startswith("classic_lstm_"):
        return ClassicLSTM(hidden_size=int(variant.rsplit("_", 1)[1]))

    classic = ClassicLSTM(hidden_size=256)
    if variant == "late_concat":
        candidate = LateConcatHistoricalLSTM()
    elif variant == "persistent_context":
        candidate = PersistentContextLSTM()
    else:
        candidate = RecentConditionedResidualLSTM()
    candidate.copy_classic_state(classic)
    return candidate