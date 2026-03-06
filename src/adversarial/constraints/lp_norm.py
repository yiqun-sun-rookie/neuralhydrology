from __future__ import annotations

import torch

from .base import BaseConstraint


class LpConstraint(BaseConstraint):
    """L-inf or L2 norm constraint on perturbation."""

    def __init__(self, epsilon: float, norm: str = "linf"):
        super().__init__(epsilon)
        assert norm in ("linf", "l2"), f"Unsupported norm: {norm}"
        self.norm = norm

    def project(self, x_clean: torch.Tensor, x_adv: torch.Tensor) -> torch.Tensor:
        delta = x_adv - x_clean

        if self.norm == "linf":
            delta = delta.clamp(-self.epsilon, self.epsilon)
        elif self.norm == "l2":
            # Per-sample L2 projection
            flat = delta.reshape(delta.shape[0], -1)
            norms = flat.norm(dim=1, keepdim=True).clamp(min=1e-8)
            scale = torch.min(torch.ones_like(norms), self.epsilon / norms)
            flat = flat * scale
            delta = flat.reshape(delta.shape)

        return x_clean + delta
