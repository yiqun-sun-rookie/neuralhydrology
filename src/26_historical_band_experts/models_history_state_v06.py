"""Equal-width historical experts that initialize a frozen recent LSTM state."""
from __future__ import annotations

from typing import Mapping

import torch
from torch import nn

from models_equal_experts_v06 import KeyedClassicLSTM, keyed_dropout
from models_v03 import ModelOutput, _append_statics, _set_forget_bias, count_trainable_parameters


_CLASSIC_TO_RECENT = {
    "lstm.weight_ih_l0": "weight_ih_l0",
    "lstm.weight_hh_l0": "weight_hh_l0",
    "lstm.bias_ih_l0": "bias_ih_l0",
    "lstm.bias_hh_l0": "bias_hh_l0",
}


class FrozenRecentHistoryState(nn.Module):
    consumed_dynamic_keys = ("recent", "medium", "old")

    def __init__(
        self,
        dynamic_size: int = 5,
        static_size: int = 27,
        hidden_size: int = 256,
        history_state_dropout: float = 0.4,
        forget_bias: float = 5.0,
    ) -> None:
        super().__init__()
        input_size = dynamic_size + static_size
        self.recent_encoder = nn.LSTM(input_size, hidden_size, batch_first=True)
        self.medium_encoder = nn.LSTM(input_size, hidden_size, batch_first=True)
        self.old_encoder = nn.LSTM(input_size, hidden_size, batch_first=True)
        self.recent_head = nn.Linear(hidden_size, 1)
        self.medium_hidden_gate = nn.Parameter(torch.zeros(hidden_size))
        self.old_hidden_gate = nn.Parameter(torch.zeros(hidden_size))
        self.medium_cell_gate = nn.Parameter(torch.zeros(hidden_size))
        self.old_cell_gate = nn.Parameter(torch.zeros(hidden_size))
        self.history_state_dropout = float(history_state_dropout)
        for recurrent in (
            self.recent_encoder,
            self.medium_encoder,
            self.old_encoder,
        ):
            _set_forget_bias(recurrent, forget_bias)

    def load_and_freeze_recent(self, base_state_dict: Mapping[str, torch.Tensor]) -> None:
        recurrent_state = {
            target: base_state_dict[source]
            for source, target in _CLASSIC_TO_RECENT.items()
        }
        self.recent_encoder.load_state_dict(recurrent_state)
        self.recent_head.load_state_dict({
            "weight": base_state_dict["head.weight"],
            "bias": base_state_dict["head.bias"],
        })
        for parameter in self.recent_encoder.parameters():
            parameter.requires_grad_(False)
        for parameter in self.recent_head.parameters():
            parameter.requires_grad_(False)

    def _history_state(
        self,
        encoder: nn.LSTM,
        values: torch.Tensor,
        statics: torch.Tensor,
        dropout_context: tuple[int, int, int] | None,
        branch: str,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        _, (hidden, cell) = encoder(_append_statics(values, statics))
        joined = torch.cat((hidden[-1], cell[-1]), dim=-1)
        dropped = keyed_dropout(
            joined,
            probability=self.history_state_dropout,
            context=dropout_context,
            branch=branch,
            training=self.training,
        )
        return dropped.chunk(2, dim=-1)

    def forward(
        self,
        dynamic: Mapping[str, torch.Tensor],
        statics: torch.Tensor,
        dropout_context: tuple[int, int, int] | None = None,
    ) -> ModelOutput:
        medium_hidden, medium_cell = self._history_state(
            self.medium_encoder,
            dynamic["medium"],
            statics,
            dropout_context,
            branch="medium_state",
        )
        old_hidden, old_cell = self._history_state(
            self.old_encoder,
            dynamic["old"],
            statics,
            dropout_context,
            branch="old_state",
        )
        initial_hidden = (
            torch.tanh(self.medium_hidden_gate) * medium_hidden
            + torch.tanh(self.old_hidden_gate) * old_hidden
        )
        initial_cell = (
            torch.tanh(self.medium_cell_gate) * medium_cell
            + torch.tanh(self.old_cell_gate) * old_cell
        )
        recent, _ = self.recent_encoder(
            _append_statics(dynamic["recent"], statics),
            (initial_hidden.unsqueeze(0), initial_cell.unsqueeze(0)),
        )
        return ModelOutput(prediction=self.recent_head(recent[:, -1])[:, 0])


def build_history_state_candidate_v06(
    base_state_dict: Mapping[str, torch.Tensor],
    seed: int,
) -> FrozenRecentHistoryState:
    torch.manual_seed(int(seed))
    _ = KeyedClassicLSTM(hidden_size=256)
    model = FrozenRecentHistoryState()
    model.load_and_freeze_recent(base_state_dict)
    if sum(parameter.numel() for parameter in model.parameters()) != 892_161:
        raise ValueError("history-state candidate parameter count is not 892161")
    if count_trainable_parameters(model) != 594_944:
        raise ValueError("trainable history-state parameter count is not 594944")
    return model
