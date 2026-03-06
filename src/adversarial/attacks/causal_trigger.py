"""Causal Trigger: perturb pre-event window to corrupt peak predictions."""
from __future__ import annotations

from typing import List, Optional

import torch

from .base import BaseAttack


class CausalTriggerAttack(BaseAttack):
    """Perturb only w days before flood peaks, exploiting LSTM memory.

    Only modifies input in [t_peak - pre_window, t_peak), but evaluates
    loss on [t_peak, t_peak + post_window].
    """

    def __init__(self, model, constraint, pre_window: int = 7,
                 post_window: int = 7, n_iter: int = 100, lr: float = 0.01,
                 target: str = "untargeted", epsilon: float = 0.3):
        super().__init__(model, constraint, target, epsilon)
        self.pre_window = pre_window
        self.post_window = post_window
        self.n_iter = n_iter
        self.lr = lr

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor,
               peak_indices: Optional[List[int]] = None) -> torch.Tensor:
        B, T, F = x_d.shape

        if peak_indices is None:
            peak_indices = self._find_peaks(y_obs)

        # Build perturbation mask: 1 in pre-event windows, 0 elsewhere
        mask = torch.zeros(B, T, device=x_d.device)
        target_mask = torch.zeros(B, T, device=x_d.device)
        for t_peak in peak_indices:
            t_start = max(0, t_peak - self.pre_window)
            mask[:, t_start:t_peak] = 1.0
            t_end = min(T, t_peak + self.post_window)
            target_mask[:, t_peak:t_end] = 1.0

        delta = torch.zeros(B, T, F, device=x_d.device, requires_grad=True)
        optimizer = torch.optim.Adam([delta], lr=self.lr)

        best_loss = torch.tensor(float("inf"))
        best_delta = torch.zeros_like(delta)

        for _ in range(self.n_iter):
            optimizer.zero_grad()

            masked_delta = delta * mask.unsqueeze(-1)
            x_adv = self.constraint.project(x_d, x_d + masked_delta)

            y_pred = self.model(x_adv, x_s)

            # Loss only on target window (peak + post)
            if target_mask.sum() > 0:
                y_pred_target = y_pred.squeeze(-1) * target_mask
                y_obs_target = y_obs.squeeze(-1) * target_mask
                n_active = target_mask.sum().clamp(min=1)
                loss = -((y_pred_target - y_obs_target) ** 2).sum() / n_active
            else:
                loss = self.compute_loss(y_pred, y_obs)

            loss.backward()
            optimizer.step()

            with torch.no_grad():
                if loss.item() < best_loss.item():
                    best_loss = loss
                    best_delta = delta.data.clone()

        with torch.no_grad():
            masked_delta = best_delta * mask.unsqueeze(-1)
            x_adv = self.constraint.project(x_d, x_d + masked_delta)
        return x_adv

    @staticmethod
    def _find_peaks(y_obs: torch.Tensor, quantile: float = 0.95) -> List[int]:
        """Auto-detect flood peaks from observations."""
        y = y_obs.squeeze(-1).mean(dim=0)  # [T]
        threshold = torch.quantile(y, quantile)
        above = (y >= threshold).nonzero(as_tuple=True)[0]
        if len(above) == 0:
            return [int(y.argmax())]
        # Cluster nearby peaks: take local maxima with min distance 14 days
        peaks = []
        last = -100
        for idx in above.tolist():
            if idx - last > 14:
                peaks.append(idx)
                last = idx
        return peaks if peaks else [int(y.argmax())]
