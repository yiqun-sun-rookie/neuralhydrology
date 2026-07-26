"""Classic controls and one hierarchical rich-history single-output model."""
from __future__ import annotations

from typing import Mapping

import torch
from torch import nn

from models_v03 import (
    ClassicLSTM,
    ModelOutput,
    _append_statics,
    _set_forget_bias,
    count_trainable_parameters,
)


VARIANTS_V05 = (
    "classic_lstm_256",
    "classic_lstm_320",
    "hierarchical_rich_history",
)


def _state_from_statics(
    projection: nn.Linear,
    statics: torch.Tensor,
) -> tuple[torch.Tensor, torch.Tensor]:
    hidden, cell = projection(statics).chunk(2, dim=-1)
    return hidden.unsqueeze(0).contiguous(), cell.unsqueeze(0).contiguous()


class HierarchicalRichHistoryLSTM(nn.Module):
    """Fuse classic recent memory with rich medium and hierarchical old memory."""

    consumed_dynamic_keys = ("recent", "medium", "old")

    def __init__(
        self,
        dynamic_size: int = 5,
        static_size: int = 27,
        recent_hidden_size: int = 256,
        medium_hidden_size: int = 64,
        old_within_hidden_size: int = 64,
        old_across_hidden_size: int = 128,
        dropout: float = 0.4,
        forget_bias: float = 5.0,
    ) -> None:
        super().__init__()
        rich_size = 4 * dynamic_size
        self.lstm = nn.LSTM(dynamic_size + static_size, recent_hidden_size, batch_first=True)
        self.medium_static_state = nn.Linear(static_size, 2 * medium_hidden_size)
        self.medium_encoder = nn.LSTM(rich_size, medium_hidden_size, batch_first=True)
        self.old_within_static_state = nn.Linear(static_size, 2 * old_within_hidden_size)
        self.old_within_encoder = nn.LSTM(rich_size, old_within_hidden_size, batch_first=True)
        self.old_across_static_state = nn.Linear(static_size, 2 * old_across_hidden_size)
        self.old_across_encoder = nn.LSTM(
            old_within_hidden_size,
            old_across_hidden_size,
            batch_first=True,
        )
        fused_size = recent_hidden_size + medium_hidden_size + old_across_hidden_size
        self.dropout = nn.Dropout(dropout)
        self.head = nn.Linear(fused_size, 1)
        for recurrent in self.recurrent_modules():
            _set_forget_bias(recurrent, forget_bias)

    def recurrent_modules(self) -> tuple[nn.LSTM, ...]:
        return (
            self.lstm,
            self.medium_encoder,
            self.old_within_encoder,
            self.old_across_encoder,
        )

    def copy_classic_state(self, classic: ClassicLSTM) -> None:
        """Copy the classic recent path and initialize history as output-neutral."""
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

        medium_initial = _state_from_statics(self.medium_static_state, statics)
        medium, _ = self.medium_encoder(dynamic["medium"], medium_initial)

        old = dynamic["old"]
        if old.ndim != 4 or old.shape[1:3] != (5, 12):
            raise ValueError("old history must have shape [N,5,12,D]")
        batch_size = old.shape[0]
        old_flat = old.reshape(batch_size * 5, 12, old.shape[-1])
        within_statics = statics.repeat_interleave(5, dim=0)
        within_initial = _state_from_statics(self.old_within_static_state, within_statics)
        within, _ = self.old_within_encoder(old_flat, within_initial)
        yearly = within[:, -1].reshape(batch_size, 5, -1)

        across_initial = _state_from_statics(self.old_across_static_state, statics)
        across, _ = self.old_across_encoder(yearly, across_initial)

        fused = torch.cat((recent[:, -1], medium[:, -1], across[:, -1]), dim=-1)
        prediction = self.head(self.dropout(fused))[:, 0]
        return ModelOutput(prediction=prediction)


def build_model_v05(variant: str, seed: int) -> nn.Module:
    """Build one deterministic version 05 candidate or classic control."""
    if variant not in VARIANTS_V05:
        raise ValueError(f"unknown variant: {variant}")
    torch.manual_seed(int(seed))
    if variant == "classic_lstm_256":
        return ClassicLSTM(hidden_size=256)
    if variant == "classic_lstm_320":
        return ClassicLSTM(hidden_size=320)

    classic = ClassicLSTM(hidden_size=256)
    candidate = HierarchicalRichHistoryLSTM()
    candidate.copy_classic_state(classic)
    return candidate
