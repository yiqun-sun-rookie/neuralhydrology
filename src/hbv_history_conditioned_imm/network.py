"""Causal history network for dynamic candidate transition probabilities."""

from __future__ import annotations

import torch
from torch import nn


FEATURE_COUNT = 21


def build_history_features(
    previous_forcing: torch.Tensor,
    previous_global_state: torch.Tensor,
    previous_posterior_probabilities: torch.Tensor,
) -> torch.Tensor:
    """Join only quantities available after the preceding day's update."""
    if previous_forcing.ndim != 2 or previous_forcing.shape[-1] != 3:
        raise ValueError("previous_forcing must have shape [batch, 3]")
    batch = previous_forcing.shape[0]
    if previous_global_state.shape != (batch, 15):
        raise ValueError("previous_global_state must have shape [batch, 15]")
    if previous_posterior_probabilities.shape != (batch, 3):
        raise ValueError("previous_posterior_probabilities must have shape [batch, 3]")
    features = torch.cat(
        (
            previous_forcing,
            previous_global_state,
            previous_posterior_probabilities,
        ),
        dim=-1,
    )
    if not torch.isfinite(features).all():
        raise ValueError("history features must be finite")
    return features


class HistoryTransitionNetwork(nn.Module):
    """Map previous-day information to a row-stochastic transition matrix."""

    def __init__(
        self,
        *,
        base_transition: torch.Tensor,
        feature_mean: torch.Tensor,
        feature_standard_deviation: torch.Tensor,
        hidden_size: int = 16,
        maximum_logit_correction: float = 2.0,
        output_parameterization: str = "full_matrix",
    ) -> None:
        super().__init__()
        base = torch.as_tensor(base_transition)
        mean = torch.as_tensor(feature_mean, dtype=base.dtype, device=base.device)
        standard_deviation = torch.as_tensor(
            feature_standard_deviation, dtype=base.dtype, device=base.device
        )
        if base.shape != (3, 3) or not torch.isfinite(base).all() or torch.any(base <= 0.0):
            raise ValueError("base_transition must be a finite positive 3 by 3 matrix")
        if mean.shape != (FEATURE_COUNT,) or standard_deviation.shape != (FEATURE_COUNT,):
            raise ValueError("normalization vectors must contain 21 values")
        if (
            not torch.isfinite(mean).all()
            or not torch.isfinite(standard_deviation).all()
            or torch.any(standard_deviation <= 0.0)
        ):
            raise ValueError("normalization values must be finite with positive standard deviations")
        if hidden_size <= 0 or maximum_logit_correction <= 0.0:
            raise ValueError("hidden size and maximum correction must be positive")
        if output_parameterization not in {"full_matrix", "shared_hazard"}:
            raise ValueError(
                "output parameterization must be full_matrix or shared_hazard"
            )
        base = base / base.sum(dim=-1, keepdim=True)
        if output_parameterization == "shared_hazard":
            common_stay = base[0, 0]
            shared_base = torch.full_like(base, (1.0 - common_stay) / 2.0)
            shared_base.fill_diagonal_(common_stay)
            if not torch.allclose(base, shared_base, rtol=0.0, atol=1e-12):
                raise ValueError(
                    "shared hazard requires one common stay probability and "
                    "equal target-direction probabilities"
                )
        self.register_buffer("base_transition", base.clone())
        self.register_buffer("feature_mean", mean.clone())
        self.register_buffer("feature_standard_deviation", standard_deviation.clone())
        self.hidden_size = int(hidden_size)
        self.maximum_logit_correction = float(maximum_logit_correction)
        self.output_parameterization = output_parameterization
        self.cell = nn.GRUCell(
            FEATURE_COUNT,
            self.hidden_size,
            dtype=base.dtype,
            device=base.device,
        )
        self.output = nn.Linear(
            self.hidden_size,
            9 if output_parameterization == "full_matrix" else 1,
            dtype=base.dtype,
            device=base.device,
        )
        nn.init.zeros_(self.output.weight)
        nn.init.zeros_(self.output.bias)

    def initial_hidden(
        self,
        batch_size: int,
        *,
        dtype: torch.dtype | None = None,
        device: torch.device | None = None,
    ) -> torch.Tensor:
        if batch_size <= 0:
            raise ValueError("batch_size must be positive")
        return torch.zeros(
            (int(batch_size), self.hidden_size),
            dtype=dtype or self.base_transition.dtype,
            device=device or self.base_transition.device,
        )

    def forward(
        self,
        previous_features: torch.Tensor,
        hidden: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        if previous_features.ndim != 2 or previous_features.shape[-1] != FEATURE_COUNT:
            raise ValueError("previous_features must have shape [batch, 21]")
        expected_hidden = (previous_features.shape[0], self.hidden_size)
        if hidden.shape != expected_hidden:
            raise ValueError(f"hidden must have shape {expected_hidden}")
        normalized = (
            previous_features - self.feature_mean
        ) / self.feature_standard_deviation
        next_hidden = self.cell(normalized, hidden)
        if self.output_parameterization == "full_matrix":
            correction = self.maximum_logit_correction * torch.tanh(
                self.output(next_hidden).reshape(-1, 3, 3)
            )
            base = self.base_transition.expand(previous_features.shape[0], -1, -1)
            calculated = torch.softmax(torch.log(base) + correction, dim=-1)
        else:
            hazard_logit_correction = (
                2.0
                * self.maximum_logit_correction
                * torch.tanh(self.output(next_hidden).reshape(-1, 1, 1))
            )
            identity = torch.eye(
                3,
                dtype=self.base_transition.dtype,
                device=self.base_transition.device,
            ).unsqueeze(0)
            correction = hazard_logit_correction * (0.5 - identity)
            base = self.base_transition.expand(previous_features.shape[0], -1, -1)
            base_hazard = 1.0 - self.base_transition[0, 0]
            base_hazard_logit = torch.log(base_hazard / (1.0 - base_hazard))
            hazard = torch.sigmoid(base_hazard_logit + hazard_logit_correction)
            calculated = identity * (1.0 - hazard) + (1.0 - identity) * (
                hazard / 2.0
            )

        # Preserve the fixed-transition calculation bit-for-bit at initialization,
        # while retaining the softmax derivative needed for the first optimizer step.
        zero_correction = torch.all(correction == 0.0, dim=(-1, -2), keepdim=True)
        exact_base_with_gradient = calculated + (base - calculated).detach()
        transition = torch.where(
            zero_correction,
            exact_base_with_gradient,
            calculated,
        )
        return transition, next_hidden, correction


class StaticTransitionNetwork(nn.Module):
    """Train one constant transition matrix without using history."""

    def __init__(
        self,
        *,
        base_transition: torch.Tensor,
        maximum_logit_correction: float = 2.0,
    ) -> None:
        super().__init__()
        base = torch.as_tensor(base_transition)
        if (
            base.shape != (3, 3)
            or not torch.isfinite(base).all()
            or torch.any(base <= 0.0)
            or maximum_logit_correction <= 0.0
        ):
            raise ValueError("base transition and maximum correction are invalid")
        base = base / base.sum(dim=-1, keepdim=True)
        self.register_buffer("base_transition", base.clone())
        self.maximum_logit_correction = float(maximum_logit_correction)
        self.raw_correction = nn.Parameter(torch.zeros_like(base))

    def initial_hidden(
        self,
        batch_size: int,
        *,
        dtype: torch.dtype | None = None,
        device: torch.device | None = None,
    ) -> torch.Tensor:
        if batch_size <= 0:
            raise ValueError("batch_size must be positive")
        return torch.zeros(
            (int(batch_size), 1),
            dtype=dtype or self.base_transition.dtype,
            device=device or self.base_transition.device,
        )

    def forward(
        self,
        previous_features: torch.Tensor,
        hidden: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        if previous_features.ndim != 2 or previous_features.shape[-1] != FEATURE_COUNT:
            raise ValueError("previous_features must have shape [batch, 21]")
        batch = previous_features.shape[0]
        if hidden.shape != (batch, 1):
            raise ValueError("static hidden state must have shape [batch, 1]")
        correction_single = self.maximum_logit_correction * torch.tanh(
            self.raw_correction
        )
        correction = correction_single.expand(batch, -1, -1)
        base = self.base_transition.expand(batch, -1, -1)
        calculated = torch.softmax(torch.log(base) + correction, dim=-1)
        zero_correction = torch.all(correction == 0.0, dim=(-1, -2), keepdim=True)
        exact_base_with_gradient = calculated + (base - calculated).detach()
        transition = torch.where(
            zero_correction,
            exact_base_with_gradient,
            calculated,
        )
        return transition, hidden, correction
