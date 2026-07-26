"""Parameter-matched model arms for the fixed historical-band pilot."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping

import torch
from torch import nn


@dataclass
class ModelOutput:
    """Common output contract across all comparison arms."""

    prediction: torch.Tensor
    weights: torch.Tensor | None = None
    expert_predictions: torch.Tensor | None = None


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


class MainstreamLSTM(nn.Module):
    """A parameter-matched 270-day mainstream Long Short-Term Memory network."""

    consumed_dynamic_keys = ("mainstream",)

    def __init__(
        self,
        dynamic_size: int,
        static_size: int,
        hidden_size: int = 128,
        dropout: float = 0.4,
    ) -> None:
        super().__init__()
        self.lstm = nn.LSTM(dynamic_size + static_size, hidden_size, batch_first=True)
        self.dropout = nn.Dropout(dropout)
        self.head = nn.Linear(hidden_size, 1)
        _set_forget_bias(self.lstm)

    def recurrent_modules(self) -> tuple[nn.LSTM, ...]:
        return (self.lstm,)

    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
    ) -> ModelOutput:
        sequence = _append_statics(dynamic["mainstream"], statics)
        encoded, _ = self.lstm(sequence)
        prediction = self.head(self.dropout(encoded[:, -1]))[:, 0]
        return ModelOutput(prediction=prediction)


class _ThreeBandBase(nn.Module):
    consumed_dynamic_keys = ("recent", "medium", "old")

    def __init__(
        self,
        dynamic_size: int,
        static_size: int,
        hidden_size: int = 64,
        dropout: float = 0.4,
    ) -> None:
        super().__init__()
        input_size = dynamic_size + static_size
        self.dynamic_size = dynamic_size
        self.static_size = static_size
        self.hidden_size = hidden_size
        self.recent_encoder = nn.LSTM(input_size, hidden_size, batch_first=True)
        self.medium_encoder = nn.LSTM(input_size, hidden_size, batch_first=True)
        self.old_encoder = nn.LSTM(input_size, hidden_size, batch_first=True)
        self.dropout = nn.Dropout(dropout)
        for recurrent in self.recurrent_modules():
            _set_forget_bias(recurrent)

    def recurrent_modules(self) -> tuple[nn.LSTM, ...]:
        return (self.recent_encoder, self.medium_encoder, self.old_encoder)

    def _encode(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        states = []
        for name, encoder in zip(self.consumed_dynamic_keys, self.recurrent_modules()):
            encoded, _ = encoder(_append_statics(dynamic[name], statics))
            states.append(encoded[:, -1])
        return tuple(states)

    def _fusion_features(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
        states: tuple[torch.Tensor, torch.Tensor, torch.Tensor],
    ) -> torch.Tensor:
        current_forcing = dynamic["recent"][:, -1]
        return torch.cat((*states, current_forcing, statics), dim=-1)


class MultiscaleFusion(_ThreeBandBase):
    """Equal-input multiscale encoder with one ordinary fusion head."""

    def __init__(
        self,
        dynamic_size: int,
        static_size: int,
        hidden_size: int = 64,
        dropout: float = 0.4,
    ) -> None:
        super().__init__(dynamic_size, static_size, hidden_size, dropout)
        fusion_size = 3 * hidden_size + dynamic_size + static_size
        self.head = nn.Sequential(
            nn.Linear(fusion_size, 32),
            nn.ReLU(),
            nn.Linear(32, 1),
        )

    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
    ) -> ModelOutput:
        states = self._encode(dynamic, statics)
        features = self._fusion_features(dynamic, statics, states)
        prediction = self.head(self.dropout(features))[:, 0]
        return ModelOutput(prediction=prediction)


class HistoricalBandExperts(_ThreeBandBase):
    """Three explicit historical-band predictions combined by a dynamic gate."""

    def __init__(
        self,
        dynamic_size: int,
        static_size: int,
        hidden_size: int = 64,
        dropout: float = 0.4,
    ) -> None:
        super().__init__(dynamic_size, static_size, hidden_size, dropout)
        self.expert_heads = nn.ModuleList([nn.Linear(hidden_size, 1) for _ in range(3)])
        fusion_size = 3 * hidden_size + dynamic_size + static_size
        self.gate = nn.Sequential(
            nn.Linear(fusion_size, 32),
            nn.ReLU(),
            nn.Linear(32, 3),
            nn.Softmax(dim=-1),
        )

    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
    ) -> ModelOutput:
        states = self._encode(dynamic, statics)
        expert_predictions = torch.cat([
            head(self.dropout(state))
            for head, state in zip(self.expert_heads, states)
        ], dim=1)
        features = self._fusion_features(dynamic, statics, states)
        weights = self.gate(features)
        prediction = (weights * expert_predictions).sum(dim=1)
        return ModelOutput(
            prediction=prediction,
            weights=weights,
            expert_predictions=expert_predictions,
        )
