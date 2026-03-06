"""Base class for all adversarial attacks."""
from __future__ import annotations

from abc import ABC, abstractmethod

import torch

from src.adversarial.constraints.base import BaseConstraint
from src.adversarial.attacks.losses import get_loss_fn


class BaseAttack(ABC):
    """Abstract base class for adversarial attacks on CudaLSTM."""

    def __init__(self, model, constraint: BaseConstraint,
                 target: str = "untargeted", epsilon: float = 0.1):
        self.model = model
        self.constraint = constraint
        self.target = target
        self.epsilon = epsilon
        self.loss_fn = get_loss_fn(target)

    @abstractmethod
    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        """Generate adversarial perturbation.

        Args:
            x_d: [B, T, F] clean dynamic features.
            x_s: [B, S] static attributes (not perturbed).
            y_obs: [B, T, 1] observed streamflow.

        Returns:
            x_d_adv: [B, T, F] adversarial dynamic features.
        """
        ...

    def compute_loss(self, y_pred: torch.Tensor,
                     y_obs: torch.Tensor) -> torch.Tensor:
        """Compute attack loss (to be MINIMIZED — lower = worse prediction)."""
        return self.loss_fn(y_pred.squeeze(-1), y_obs.squeeze(-1))
