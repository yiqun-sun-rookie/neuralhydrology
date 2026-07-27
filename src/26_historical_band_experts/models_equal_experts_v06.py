"""Classic controls and three equal historical LSTM experts with keyed dropout."""
from __future__ import annotations

import hashlib
from typing import Mapping

import torch
from torch import nn

from models_v03 import ModelOutput, _append_statics, _set_forget_bias


VARIANTS_EQUAL_EXPERTS_V06 = (
    "classic_lstm_256_keyed",
    "classic_lstm_455_keyed",
    "late_concat_keyed",
    "equal_experts",
)


def _dropout_seed(context: tuple[int, int, int], branch: str) -> int:
    seed, epoch, batch_index = (int(value) for value in context)
    payload = f"{seed}:{epoch}:{batch_index}:{branch}".encode("utf-8")
    return int.from_bytes(hashlib.sha256(payload).digest()[:8], "little") % (2**63 - 1)


def keyed_dropout(
    values: torch.Tensor,
    probability: float,
    context: tuple[int, int, int] | None,
    branch: str,
    training: bool,
) -> torch.Tensor:
    """Apply deterministic branch-specific dropout without advancing global RNG."""
    if not training or probability == 0:
        return values
    if context is None:
        raise ValueError("dropout_context is required during training")
    if not 0 <= probability < 1:
        raise ValueError("dropout probability must be in [0,1)")
    generator = torch.Generator(device=values.device)
    generator.manual_seed(_dropout_seed(context, branch))
    keep = torch.rand(
        values.shape,
        dtype=torch.float32,
        device=values.device,
        generator=generator,
    ) >= probability
    return values * keep.to(dtype=values.dtype) / (1.0 - probability)


class KeyedClassicLSTM(nn.Module):
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
        self.lstm = nn.LSTM(dynamic_size + static_size, hidden_size, batch_first=True)
        self.head = nn.Linear(hidden_size, 1)
        self.dropout_probability = float(dropout)
        _set_forget_bias(self.lstm, forget_bias)

    def recurrent_modules(self) -> tuple[nn.LSTM, ...]:
        return (self.lstm,)

    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
        dropout_context: tuple[int, int, int] | None = None,
    ) -> ModelOutput:
        recent, _ = self.lstm(_append_statics(dynamic["recent"], statics))
        dropped = keyed_dropout(
            recent[:, -1],
            self.dropout_probability,
            dropout_context,
            branch="recent",
            training=self.training,
        )
        return ModelOutput(prediction=self.head(dropped)[:, 0])


class KeyedLateConcat(nn.Module):
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
        self.recent_head = nn.Linear(recent_hidden_size, 1)
        self.medium_head = nn.Linear(history_hidden_size, 1, bias=False)
        self.old_head = nn.Linear(history_hidden_size, 1, bias=False)
        self.dropout_probability = float(dropout)
        for recurrent in self.recurrent_modules():
            _set_forget_bias(recurrent, forget_bias)

    def recurrent_modules(self) -> tuple[nn.LSTM, ...]:
        return (self.lstm, self.medium_encoder, self.old_encoder)

    def copy_classic_state(self, classic: KeyedClassicLSTM) -> None:
        self.lstm.load_state_dict(classic.lstm.state_dict())
        self.recent_head.load_state_dict(classic.head.state_dict())
        with torch.no_grad():
            self.medium_head.weight.zero_()
            self.old_head.weight.zero_()

    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
        dropout_context: tuple[int, int, int] | None = None,
    ) -> ModelOutput:
        recent, _ = self.lstm(_append_statics(dynamic["recent"], statics))
        medium, _ = self.medium_encoder(_append_statics(dynamic["medium"], statics))
        old, _ = self.old_encoder(_append_statics(dynamic["old"], statics))
        recent_state = keyed_dropout(
            recent[:, -1], self.dropout_probability, dropout_context, "recent", self.training
        )
        medium_state = keyed_dropout(
            medium[:, -1], self.dropout_probability, dropout_context, "medium", self.training
        )
        old_state = keyed_dropout(
            old[:, -1], self.dropout_probability, dropout_context, "old", self.training
        )
        prediction = (
            self.recent_head(recent_state)
            + self.medium_head(medium_state)
            + self.old_head(old_state)
        )[:, 0]
        return ModelOutput(prediction=prediction)


class EqualHistoricalExperts(nn.Module):
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
        self.recent_encoder = nn.LSTM(input_size, hidden_size, batch_first=True)
        self.medium_encoder = nn.LSTM(input_size, hidden_size, batch_first=True)
        self.old_encoder = nn.LSTM(input_size, hidden_size, batch_first=True)
        self.recent_head = nn.Linear(hidden_size, 1)
        self.medium_head = nn.Linear(hidden_size, 1, bias=False)
        self.old_head = nn.Linear(hidden_size, 1, bias=False)
        self.dropout_probability = float(dropout)
        for recurrent in self.recurrent_modules():
            _set_forget_bias(recurrent, forget_bias)

    def recurrent_modules(self) -> tuple[nn.LSTM, ...]:
        return (self.recent_encoder, self.medium_encoder, self.old_encoder)

    def copy_classic_state(self, classic: KeyedClassicLSTM) -> None:
        self.recent_encoder.load_state_dict(classic.lstm.state_dict())
        self.recent_head.load_state_dict(classic.head.state_dict())
        with torch.no_grad():
            self.medium_head.weight.zero_()
            self.old_head.weight.zero_()

    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
        dropout_context: tuple[int, int, int] | None = None,
    ) -> ModelOutput:
        recent, _ = self.recent_encoder(_append_statics(dynamic["recent"], statics))
        medium, _ = self.medium_encoder(_append_statics(dynamic["medium"], statics))
        old, _ = self.old_encoder(_append_statics(dynamic["old"], statics))
        recent_state = keyed_dropout(
            recent[:, -1], self.dropout_probability, dropout_context, "recent", self.training
        )
        medium_state = keyed_dropout(
            medium[:, -1], self.dropout_probability, dropout_context, "medium", self.training
        )
        old_state = keyed_dropout(
            old[:, -1], self.dropout_probability, dropout_context, "old", self.training
        )
        prediction = (
            self.recent_head(recent_state)
            + self.medium_head(medium_state)
            + self.old_head(old_state)
        )[:, 0]
        return ModelOutput(prediction=prediction)


def build_equal_experts_model_v06(variant: str, seed: int) -> nn.Module:
    if variant not in VARIANTS_EQUAL_EXPERTS_V06:
        raise ValueError(f"unknown equal-expert variant: {variant}")
    torch.manual_seed(int(seed))
    if variant == "classic_lstm_256_keyed":
        return KeyedClassicLSTM(hidden_size=256)
    if variant == "classic_lstm_455_keyed":
        return KeyedClassicLSTM(hidden_size=455)

    classic = KeyedClassicLSTM(hidden_size=256)
    if variant == "late_concat_keyed":
        candidate = KeyedLateConcat()
    else:
        candidate = EqualHistoricalExperts()
    candidate.copy_classic_state(classic)
    return candidate
