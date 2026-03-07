"""C&W adapted for regression: minimize perturbation s.t. NSE < target."""
from __future__ import annotations

import torch

from .base import BaseAttack


class CWRegression(BaseAttack):
    """Carlini-Wagner attack adapted for regression (streamflow).

    Finds minimum L2 perturbation such that NSE drops below target_nse.
    """

    def __init__(self, model, constraint, target_nse: float = 0.0,
                 n_iter: int = 200, lr: float = 0.01,
                 c_init: float = 1.0, c_factor: float = 2.0,
                 binary_search_steps: int = 5,
                 target: str = "untargeted", epsilon: float = 1.0):
        super().__init__(model, constraint, target, epsilon)
        self.target_nse = target_nse
        self.n_iter = n_iter
        self.lr = lr
        self.c_init = c_init
        self.c_factor = c_factor
        self.binary_search_steps = binary_search_steps

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        best_adv = x_d.clone()
        best_l2 = torch.tensor(float("inf"))
        # Track best-effort (lowest NSE achieved) in case no step succeeds
        best_effort_adv = x_d.clone()
        best_effort_nse = torch.tensor(float("inf"))

        c_lo, c_hi = 0.0, self.c_init * 10.0
        c = self.c_init

        for _ in range(self.binary_search_steps):
            x_adv, success, final_nse = self._optimize(x_d, x_s, y_obs, c)
            l2 = (x_adv - x_d).reshape(x_d.shape[0], -1).norm(dim=1).mean()

            if final_nse < best_effort_nse:
                best_effort_nse = final_nse
                best_effort_adv = x_adv.clone()

            if success and l2 < best_l2:
                best_l2 = l2
                best_adv = x_adv.clone()
                c_hi = c
            else:
                c_lo = c

            c = (c_lo + c_hi) / 2.0

        # If no step achieved target, return best-effort (most damage)
        if best_l2 == float("inf"):
            return best_effort_adv
        return best_adv

    def _optimize(self, x_d, x_s, y_obs, c):
        w = torch.zeros_like(x_d, requires_grad=True)
        optimizer = torch.optim.Adam([w], lr=self.lr)

        for _ in range(self.n_iter):
            optimizer.zero_grad()
            delta = torch.tanh(w) * self.epsilon
            x_adv = self.constraint.project(x_d, x_d + delta)

            y_pred = self.model(x_adv, x_s)
            nse = self.compute_loss(y_pred, y_obs)

            # L2 norm of perturbation
            l2 = (x_adv - x_d).reshape(x_d.shape[0], -1).norm(dim=1).mean()

            # C&W objective: minimize L2 + c * max(0, NSE - target)
            attack_term = torch.clamp(nse - self.target_nse, min=0.0)
            loss = l2 + c * attack_term

            loss.backward()
            optimizer.step()

        with torch.no_grad():
            delta = torch.tanh(w) * self.epsilon
            x_adv = self.constraint.project(x_d, x_d + delta)
            y_pred = self.model(x_adv, x_s)
            final_nse = self.compute_loss(y_pred, y_obs)
            success = final_nse.item() <= self.target_nse

        return x_adv.detach(), success, final_nse.item()
