"""Zero-tolerance recent-only nested control for strict training reproduction."""
from __future__ import annotations

import copy
from typing import Mapping

import torch
from torch import nn

from models_v03 import ClassicLSTM, ModelOutput, _append_statics, _set_forget_bias


class StrictRecentNestedControl(nn.Module):
    """Classic recent path plus frozen history modules that are never executed."""

    consumed_dynamic_keys = ("recent",)

    def __init__(self, classic: ClassicLSTM) -> None:
        super().__init__()
        self.lstm = copy.deepcopy(classic.lstm)
        self.dropout = copy.deepcopy(classic.dropout)
        self.head = copy.deepcopy(classic.head)
        with torch.random.fork_rng(devices=[]):
            self.inert_history = nn.ModuleDict({
                "medium": nn.LSTM(32, 256, batch_first=True),
                "old": nn.LSTM(32, 256, batch_first=True),
            })
            for recurrent in self.inert_history.values():
                _set_forget_bias(recurrent, 5.0)
        for parameter in self.inert_history.parameters():
            parameter.requires_grad_(False)

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


def build_strict_pair_v06(seed: int) -> tuple[ClassicLSTM, StrictRecentNestedControl]:
    """Build a classic reference and nested control without advancing past classic RNG state."""
    torch.manual_seed(int(seed))
    classic = ClassicLSTM(hidden_size=256)
    nested = StrictRecentNestedControl(classic)
    return classic, nested
