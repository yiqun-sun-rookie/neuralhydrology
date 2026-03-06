"""Auto-PGD: adaptive step-size PGD attack."""
from __future__ import annotations

import torch

from .base import BaseAttack


class AutoPGD(BaseAttack):
    """Auto-PGD with adaptive step size and checkpoint restarts.

    Reference: Croce & Hein (2020), "Reliable evaluation of adversarial
    robustness with an ensemble of diverse parameter-free attacks."
    """

    def __init__(self, model, constraint, n_iter: int = 50,
                 target: str = "untargeted", epsilon: float = 0.1,
                 n_restarts: int = 1, rho: float = 0.75):
        super().__init__(model, constraint, target, epsilon)
        self.n_iter = n_iter
        self.n_restarts = n_restarts
        self.rho = rho

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        best_adv = x_d.clone()
        best_loss = torch.tensor(float("inf"))

        for _ in range(self.n_restarts):
            x_adv = self._single_run(x_d, x_s, y_obs)
            with torch.no_grad():
                y_adv = self.model(x_adv, x_s)
                loss = self.compute_loss(y_adv, y_obs)
            if loss < best_loss:
                best_loss = loss
                best_adv = x_adv.clone()

        return best_adv

    def _single_run(self, x_d: torch.Tensor, x_s: torch.Tensor,
                    y_obs: torch.Tensor) -> torch.Tensor:
        # Initialize with random perturbation within epsilon ball
        delta = torch.empty_like(x_d).uniform_(-self.epsilon, self.epsilon)
        delta.requires_grad_(True)

        # Adaptive step size schedule
        eta = 2.0 * self.epsilon
        checkpoints = [int(self.rho ** i * self.n_iter) for i in range(10)]
        checkpoints = sorted(set(c for c in checkpoints if 0 < c < self.n_iter))

        best_loss = torch.tensor(float("inf"))
        best_delta = delta.data.clone()
        prev_loss = None
        n_worse = 0

        for i in range(self.n_iter):
            x_adv = self.constraint.project(x_d, x_d + delta)
            x_adv_input = x_adv.detach().requires_grad_(True)

            y_pred = self.model(x_adv_input, x_s)
            loss = self.compute_loss(y_pred, y_obs)

            if loss < best_loss:
                best_loss = loss.item()
                best_delta = (x_adv_input - x_d).detach().clone()

            loss.backward()

            with torch.no_grad():
                grad = x_adv_input.grad
                # PGD step: move in direction of negative gradient (minimize NSE)
                delta.data = best_delta - eta * grad.sign()
                # Project
                x_proj = self.constraint.project(x_d, x_d + delta.data)
                delta.data = x_proj - x_d

                # Adaptive step size: halve if no progress
                if prev_loss is not None and loss.item() >= prev_loss:
                    n_worse += 1
                else:
                    n_worse = 0
                prev_loss = loss.item()

                if i in checkpoints or n_worse >= 3:
                    eta = eta / 2.0
                    n_worse = 0
                    delta.data = best_delta.clone()

        return x_d + best_delta
