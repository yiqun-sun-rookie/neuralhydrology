"""Random noise baselines: Gaussian, multiplicative bias, time-correlated."""
from __future__ import annotations

import torch

from .base import BaseAttack


class GaussianNoise(BaseAttack):
    """Add i.i.d. Gaussian noise clamped to epsilon-ball.

    Non-adversarial baseline: random direction, same perturbation budget.
    """

    def __init__(self, model, constraint, target: str = "untargeted",
                 epsilon: float = 0.1, n_samples: int = 10, seed: int = 42):
        super().__init__(model, constraint, target, epsilon)
        self.n_samples = n_samples
        self.seed = seed

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        gen = torch.Generator(device=x_d.device).manual_seed(self.seed)
        best_adv = x_d.clone()
        best_loss = torch.tensor(float("inf"))

        for _ in range(self.n_samples):
            noise = torch.randn(x_d.shape, generator=gen, device=x_d.device) * self.epsilon
            x_noisy = self.constraint.project(x_d, x_d + noise)

            with torch.no_grad():
                y_pred = self.model(x_noisy, x_s)
                loss = self.compute_loss(y_pred, y_obs)

            if loss < best_loss:
                best_loss = loss
                best_adv = x_noisy.clone()

        return best_adv


class MultiplicativeBias(BaseAttack):
    """Multiplicative precipitation bias (realistic sensor error model).

    Applies (1 + bias) scaling to precipitation channel only.
    Bias magnitude controlled by epsilon.
    """

    def __init__(self, model, constraint, target: str = "untargeted",
                 epsilon: float = 0.1, prcp_channel: int = 0,
                 n_samples: int = 10, seed: int = 42):
        super().__init__(model, constraint, target, epsilon)
        self.prcp_channel = prcp_channel
        self.n_samples = n_samples
        self.seed = seed

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        gen = torch.Generator(device=x_d.device).manual_seed(self.seed)
        best_adv = x_d.clone()
        best_loss = torch.tensor(float("inf"))

        for _ in range(self.n_samples):
            bias = (torch.rand(1, generator=gen, device=x_d.device) * 2 - 1) * self.epsilon
            x_biased = x_d.clone()
            x_biased[:, :, self.prcp_channel] = x_d[:, :, self.prcp_channel] * (1.0 + bias)
            x_biased = self.constraint.project(x_d, x_biased)

            with torch.no_grad():
                y_pred = self.model(x_biased, x_s)
                loss = self.compute_loss(y_pred, y_obs)

            if loss < best_loss:
                best_loss = loss
                best_adv = x_biased.clone()

        return best_adv


class TemporalCorrelatedNoise(BaseAttack):
    """Time-correlated noise via smoothed random walk.

    More realistic than i.i.d. Gaussian: sensor drift, systematic bias that
    changes slowly over time.
    """

    def __init__(self, model, constraint, target: str = "untargeted",
                 epsilon: float = 0.1, smoothing: int = 7,
                 n_samples: int = 10, seed: int = 42):
        super().__init__(model, constraint, target, epsilon)
        self.smoothing = smoothing
        self.n_samples = n_samples
        self.seed = seed

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        gen = torch.Generator(device=x_d.device).manual_seed(self.seed)
        best_adv = x_d.clone()
        best_loss = torch.tensor(float("inf"))

        B, T, F = x_d.shape
        kernel = torch.ones(1, 1, self.smoothing, device=x_d.device) / self.smoothing

        for _ in range(self.n_samples):
            raw = torch.randn(B, T, F, generator=gen, device=x_d.device)
            # Smooth each feature channel with moving average
            smoothed = torch.zeros_like(raw)
            for f in range(F):
                padded = torch.nn.functional.pad(
                    raw[:, :, f:f+1].permute(0, 2, 1),
                    (self.smoothing // 2, self.smoothing // 2),
                    mode="reflect",
                )
                smoothed[:, :, f] = torch.nn.functional.conv1d(padded, kernel).squeeze(1)
            # Normalize to epsilon scale
            max_abs = smoothed.abs().amax(dim=(1, 2), keepdim=True).clamp(min=1e-10)
            noise = smoothed / max_abs * self.epsilon

            x_noisy = self.constraint.project(x_d, x_d + noise)
            with torch.no_grad():
                y_pred = self.model(x_noisy, x_s)
                loss = self.compute_loss(y_pred, y_obs)

            if loss < best_loss:
                best_loss = loss
                best_adv = x_noisy.clone()

        return best_adv
