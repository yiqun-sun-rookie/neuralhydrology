"""FGSM: Fast Gradient Sign Method (single-step baseline)."""
from __future__ import annotations

import torch

from .base import BaseAttack


class FGSM(BaseAttack):
    """Single-step FGSM attack.

    Baseline method used in prior hydrology adversarial robustness work.
    Serves as comparison to iterative methods (Auto-PGD).

    Reference: Goodfellow et al. (2015), "Explaining and Harnessing
    Adversarial Examples."
    """

    def __init__(self, model, constraint, target: str = "untargeted",
                 epsilon: float = 0.1):
        super().__init__(model, constraint, target, epsilon)

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        x_input = x_d.clone().detach().requires_grad_(True)

        y_pred = self.model(x_input, x_s)
        loss = self.compute_loss(y_pred, y_obs)
        loss.backward()

        with torch.no_grad():
            # Single step in negative gradient sign direction (minimize NSE)
            x_adv = x_d - self.epsilon * x_input.grad.sign()
            x_adv = self.constraint.project(x_d, x_adv)

        return x_adv
