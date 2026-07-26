"""Classic Long Short-Term Memory controls and single-output historical extensions."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping

import torch
from torch import nn


VARIANTS_V03 = (
    "classic_lstm_256",
    "classic_lstm_261",
    "classic_lstm_266",
    "late_concat",
    "initial_memory",
)


@dataclass
class ModelOutput:
    """The shared version 03 contract: exactly one predicted flow."""

    prediction: torch.Tensor


def count_trainable_parameters(model: nn.Module) -> int:
    return sum(parameter.numel() for parameter in model.parameters() if parameter.requires_grad)


def _set_forget_bias(lstm: nn.LSTM, value: float = 5.0) -> None:
    hidden_size = lstm.hidden_size
    with torch.no_grad():
        lstm.bias_hh_l0[hidden_size:2 * hidden_size] = value


def _append_statics(sequence: torch.Tensor, statics: torch.Tensor) -> torch.Tensor:
    if sequence.ndim != 3 or statics.ndim != 2:
        raise ValueError("sequence and statics must have shapes [N,T,D] and [N,S]")
    if sequence.shape[0] != statics.shape[0]:
        raise ValueError("sequence and statics batch sizes differ")
    repeated = statics.unsqueeze(1).expand(-1, sequence.shape[1], -1)
    return torch.cat((sequence, repeated), dim=-1)


class ClassicLSTM(nn.Module):
    """The classic hydrology LSTM with one recurrent layer and one flow head."""

    consumed_dynamic_keys = ("recent",)

    def __init__(
        self,
        dynamic_size: int = 5,
        static_size: int = 27,
        hidden_size: int = 256,
        dropout: float = 0.4,
        forget_bias: float = 5.0,
    ) -> None:
        super().__init__()
        self.lstm = nn.LSTM(dynamic_size + static_size, hidden_size, batch_first=True)
        self.dropout = nn.Dropout(dropout)
        self.head = nn.Linear(hidden_size, 1)
        _set_forget_bias(self.lstm, forget_bias)

    def recurrent_modules(self) -> tuple[nn.LSTM, ...]:
        return (self.lstm,)

    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
    ) -> ModelOutput:
        encoded, _ = self.lstm(_append_statics(dynamic["recent"], statics))
        prediction = self.head(self.dropout(encoded[:, -1]))[:, 0]
        return ModelOutput(prediction=prediction)


class LateConcatHistoricalLSTM(nn.Module):
    """Append two older-history states before one common linear flow head."""

    consumed_dynamic_keys = ("recent", "medium", "old")

    def __init__(
        self,
        dynamic_size: int = 5,
        static_size: int = 27,
        recent_hidden_size: int = 256,
        history_hidden_size: int = 24,
        dropout: float = 0.4,
        forget_bias: float = 5.0,
    ) -> None:
        super().__init__()
        input_size = dynamic_size + static_size
        self.lstm = nn.LSTM(input_size, recent_hidden_size, batch_first=True)
        self.medium_encoder = nn.LSTM(input_size, history_hidden_size, batch_first=True)
        self.old_encoder = nn.LSTM(input_size, history_hidden_size, batch_first=True)
        self.dropout = nn.Dropout(dropout)
        self.head = nn.Linear(recent_hidden_size + 2 * history_hidden_size, 1)
        for recurrent in self.recurrent_modules():
            _set_forget_bias(recurrent, forget_bias)

    def recurrent_modules(self) -> tuple[nn.LSTM, ...]:
        return (self.lstm, self.medium_encoder, self.old_encoder)

    def copy_classic_state(self, classic: ClassicLSTM) -> None:
        """Copy the classic backbone and make added features initially neutral."""
        if self.lstm.hidden_size != classic.lstm.hidden_size:
            raise ValueError("recent hidden size does not match classic reference")
        self.lstm.load_state_dict(classic.lstm.state_dict())
        with torch.no_grad():
            self.head.weight.zero_()
            self.head.weight[:, :classic.lstm.hidden_size].copy_(classic.head.weight)
            self.head.bias.copy_(classic.head.bias)

    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
    ) -> ModelOutput:
        recent, _ = self.lstm(_append_statics(dynamic["recent"], statics))
        medium, _ = self.medium_encoder(_append_statics(dynamic["medium"], statics))
        old, _ = self.old_encoder(_append_statics(dynamic["old"], statics))
        features = torch.cat((recent[:, -1], medium[:, -1], old[:, -1]), dim=-1)
        prediction = self.head(self.dropout(features))[:, 0]
        return ModelOutput(prediction=prediction)


class InitialMemoryHistoricalLSTM(nn.Module):
    """Use older-history states as the recent LSTM's initial memory state."""

    consumed_dynamic_keys = ("recent", "medium", "old")

    def __init__(
        self,
        dynamic_size: int = 5,
        static_size: int = 27,
        recent_hidden_size: int = 256,
        history_hidden_size: int = 24,
        dropout: float = 0.4,
        forget_bias: float = 5.0,
    ) -> None:
        super().__init__()
        input_size = dynamic_size + static_size
        self.lstm = nn.LSTM(input_size, recent_hidden_size, batch_first=True)
        self.medium_encoder = nn.LSTM(input_size, history_hidden_size, batch_first=True)
        self.old_encoder = nn.LSTM(input_size, history_hidden_size, batch_first=True)
        self.history_to_cell = nn.Linear(2 * history_hidden_size, recent_hidden_size)
        self.dropout = nn.Dropout(dropout)
        self.head = nn.Linear(recent_hidden_size, 1)
        for recurrent in self.recurrent_modules():
            _set_forget_bias(recurrent, forget_bias)

    def recurrent_modules(self) -> tuple[nn.LSTM, ...]:
        return (self.lstm, self.medium_encoder, self.old_encoder)

    def copy_classic_state(self, classic: ClassicLSTM) -> None:
        """Copy the classic model and make the historical memory initially zero."""
        if self.lstm.hidden_size != classic.lstm.hidden_size:
            raise ValueError("recent hidden size does not match classic reference")
        self.lstm.load_state_dict(classic.lstm.state_dict())
        self.head.load_state_dict(classic.head.state_dict())
        with torch.no_grad():
            self.history_to_cell.weight.zero_()
            self.history_to_cell.bias.zero_()

    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
    ) -> ModelOutput:
        medium, _ = self.medium_encoder(_append_statics(dynamic["medium"], statics))
        old, _ = self.old_encoder(_append_statics(dynamic["old"], statics))
        history = torch.cat((medium[:, -1], old[:, -1]), dim=-1)
        initial_cell = self.history_to_cell(history).unsqueeze(0)
        initial_hidden = torch.zeros_like(initial_cell)
        recent, _ = self.lstm(
            _append_statics(dynamic["recent"], statics),
            (initial_hidden, initial_cell),
        )
        prediction = self.head(self.dropout(recent[:, -1]))[:, 0]
        return ModelOutput(prediction=prediction)


def build_model_v03(variant: str, seed: int) -> nn.Module:
    """Build one deterministic arm, nesting candidates in the same classic seed."""
    if variant not in VARIANTS_V03:
        raise ValueError(f"unknown variant: {variant}")
    torch.manual_seed(int(seed))
    if variant == "classic_lstm_256":
        return ClassicLSTM(hidden_size=256)
    if variant == "classic_lstm_261":
        return ClassicLSTM(hidden_size=261)
    if variant == "classic_lstm_266":
        return ClassicLSTM(hidden_size=266)

    classic = ClassicLSTM(hidden_size=256)
    if variant == "late_concat":
        candidate = LateConcatHistoricalLSTM()
    else:
        candidate = InitialMemoryHistoricalLSTM()
    candidate.copy_classic_state(classic)
    return candidate
