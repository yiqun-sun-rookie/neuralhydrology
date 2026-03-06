"""Spectral Attack: perturb in frequency domain, preserve time-domain stats."""
from __future__ import annotations

import torch

from .base import BaseAttack


class SpectralAttack(BaseAttack):
    """Optimize perturbation in frequency domain.

    Perturbs selected frequency bands while keeping the DC component
    (mean) and overall energy (variance) approximately fixed.
    """

    def __init__(self, model, constraint, n_iter: int = 100,
                 lr: float = 0.01, target: str = "untargeted",
                 epsilon: float = 0.3,
                 freq_bands: str = "all"):
        super().__init__(model, constraint, target, epsilon)
        self.n_iter = n_iter
        self.lr = lr
        self.freq_bands = freq_bands  # "all", "low", "mid", "high"

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        B, T, F = x_d.shape

        x_freq = torch.fft.rfft(x_d, dim=1)  # [B, T//2+1, F] complex
        n_freq = x_freq.shape[1]

        delta_real = torch.zeros(B, n_freq, F, device=x_d.device, requires_grad=True)
        delta_imag = torch.zeros(B, n_freq, F, device=x_d.device, requires_grad=True)

        optimizer = torch.optim.Adam([delta_real, delta_imag], lr=self.lr)

        freq_mask = self._get_freq_mask(n_freq, T, x_d.device)

        best_loss = torch.tensor(float("inf"))
        best_adv = x_d.clone()

        for _ in range(self.n_iter):
            optimizer.zero_grad()

            delta_freq = torch.complex(delta_real, delta_imag)
            delta_freq = delta_freq.clone()
            delta_freq[:, 0, :] = 0.0  # preserve DC = preserve mean
            delta_freq = delta_freq * freq_mask.unsqueeze(0).unsqueeze(-1)

            delta_time = torch.fft.irfft(delta_freq, n=T, dim=1)  # [B, T, F]

            x_adv = self.constraint.project(x_d, x_d + delta_time)
            y_pred = self.model(x_adv, x_s)
            loss = self.compute_loss(y_pred, y_obs)

            loss.backward()
            optimizer.step()

            with torch.no_grad():
                if loss.item() < best_loss.item():
                    best_loss = loss
                    best_adv = x_adv.detach().clone()

        return best_adv

    def _get_freq_mask(self, n_freq: int, T: int,
                       device: torch.device) -> torch.Tensor:
        """Binary mask selecting which frequency bands to perturb."""
        mask = torch.ones(n_freq, device=device)

        if self.freq_bands == "low":
            cutoff = max(1, T // 30)
            mask[cutoff:] = 0.0
        elif self.freq_bands == "mid":
            lo = max(1, T // 30)
            hi = max(lo + 1, T // 7)
            mask[:lo] = 0.0
            mask[hi:] = 0.0
        elif self.freq_bands == "high":
            cutoff = max(1, T // 7)
            mask[:cutoff] = 0.0

        mask[0] = 0.0  # always preserve DC
        return mask
