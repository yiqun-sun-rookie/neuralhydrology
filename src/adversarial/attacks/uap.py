"""Universal Adversarial Perturbation: one pattern to attack all samples."""
from __future__ import annotations

from typing import List, Tuple, Optional

import torch

from .base import BaseAttack


class UAP(BaseAttack):
    """Craft a single universal perturbation that degrades all samples.

    Two-phase usage:
    1. craft_universal(dataset) -- optimize delta* on training data
    2. attack(x_d, x_s, y_obs) -- apply pre-computed delta* to new samples
    """

    def __init__(self, model, constraint, n_iter: int = 50,
                 lr: float = 0.01, target: str = "untargeted",
                 epsilon: float = 0.2):
        super().__init__(model, constraint, target, epsilon)
        self.n_iter = n_iter
        self.lr = lr
        self._uap: Optional[torch.Tensor] = None

    def craft_universal(
        self,
        dataset: List[Tuple[torch.Tensor, torch.Tensor, torch.Tensor]],
    ) -> torch.Tensor:
        """Optimize universal perturbation over dataset.

        Args:
            dataset: list of (x_d [1,T,F], x_s [1,S], y_obs [1,T,1]) tuples.

        Returns:
            uap: [1, T, F] universal perturbation.
        """
        x_d_0, _, _ = dataset[0]
        T, F = x_d_0.shape[1], x_d_0.shape[2]
        device = x_d_0.device

        delta = torch.zeros(1, T, F, device=device, requires_grad=True)
        optimizer = torch.optim.Adam([delta], lr=self.lr)

        for _ in range(self.n_iter):
            total_loss = torch.tensor(0.0, device=device)

            for x_d, x_s, y_obs in dataset:
                optimizer.zero_grad()
                x_adv = self.constraint.project(x_d, x_d + delta)
                y_pred = self.model(x_adv, x_s)
                loss = self.compute_loss(y_pred, y_obs)
                total_loss = total_loss + loss

            avg_loss = total_loss / len(dataset)
            avg_loss.backward()
            optimizer.step()

            with torch.no_grad():
                delta.data = delta.data.clamp(-self.epsilon, self.epsilon)

        self._uap = delta.detach().clone()
        return self._uap

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        """Apply pre-computed UAP to new samples."""
        if self._uap is None:
            raise RuntimeError("Call craft_universal() first.")
        uap = self._uap.to(x_d.device)
        x_adv = self.constraint.project(x_d, x_d + uap)
        return x_adv
