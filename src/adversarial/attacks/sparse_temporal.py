"""Sparse Temporal Attack: learn which timesteps to perturb."""
from __future__ import annotations

import torch

from .base import BaseAttack


class SparseTemporalAttack(BaseAttack):
    """Perturb only a learned subset of timesteps via Gumbel-Softmax mask.

    Jointly optimizes WHAT to perturb (mask) and HOW to perturb (delta).
    """

    def __init__(self, model, constraint, max_steps: int = 18,
                 n_iter: int = 100, lr: float = 0.01,
                 temperature: float = 1.0, temp_anneal: float = 0.95,
                 target: str = "untargeted", epsilon: float = 0.2):
        super().__init__(model, constraint, target, epsilon)
        self.max_steps = max_steps
        self.n_iter = n_iter
        self.lr = lr
        self.temperature = temperature
        self.temp_anneal = temp_anneal

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        B, T, F = x_d.shape

        mask_logits = torch.zeros(B, T, device=x_d.device, requires_grad=True)
        delta = torch.zeros(B, T, F, device=x_d.device, requires_grad=True)

        optimizer = torch.optim.Adam([mask_logits, delta], lr=self.lr)
        temp = self.temperature

        best_loss = torch.tensor(float("inf"))
        best_adv = x_d.clone()

        for i in range(self.n_iter):
            optimizer.zero_grad()

            soft_mask = self._gumbel_topk(mask_logits, self.max_steps, temp)
            masked_delta = delta * soft_mask.unsqueeze(-1)
            x_adv = self.constraint.project(x_d, x_d + masked_delta)

            y_pred = self.model(x_adv, x_s)
            loss = self.compute_loss(y_pred, y_obs)

            sparsity_loss = (soft_mask.sum(dim=1) - self.max_steps).pow(2).mean()
            total_loss = loss + 0.1 * sparsity_loss

            total_loss.backward()
            optimizer.step()

            temp *= self.temp_anneal

            with torch.no_grad():
                if loss.item() < best_loss.item():
                    best_loss = loss
                    hard_mask = self._hard_topk(mask_logits, self.max_steps)
                    hard_delta = delta * hard_mask.unsqueeze(-1)
                    best_adv = self.constraint.project(x_d, x_d + hard_delta)

        return best_adv.detach()

    @staticmethod
    def _gumbel_topk(logits: torch.Tensor, k: int,
                     temperature: float) -> torch.Tensor:
        """Differentiable top-k via Gumbel-Sigmoid."""
        gumbel = -torch.log(-torch.log(torch.rand_like(logits) + 1e-20) + 1e-20)
        perturbed = (logits + gumbel) / max(temperature, 0.01)
        return torch.sigmoid(perturbed)

    @staticmethod
    def _hard_topk(logits: torch.Tensor, k: int) -> torch.Tensor:
        """Hard top-k mask (non-differentiable, for final output)."""
        _, indices = logits.topk(k, dim=-1)
        mask = torch.zeros_like(logits)
        mask.scatter_(1, indices, 1.0)
        return mask
