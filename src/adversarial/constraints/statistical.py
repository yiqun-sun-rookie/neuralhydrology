from __future__ import annotations

from typing import List

import torch

from .physical import PhysicalConstraint


class StatisticalConstraint(PhysicalConstraint):
    """Physical + distribution-preserving (mean/std preservation)."""

    def __init__(self, epsilon: float, feature_names: List[str],
                 scaler_center: torch.Tensor, scaler_scale: torch.Tensor,
                 norm: str = "linf"):
        super().__init__(epsilon, feature_names, scaler_center, scaler_scale, norm)

    def project(self, x_clean: torch.Tensor, x_adv: torch.Tensor) -> torch.Tensor:
        # First apply physical projection
        x_proj = super().project(x_clean, x_adv)

        # Then adjust to match mean and std of original per feature (autograd-safe)
        channels = []
        for f in range(x_proj.shape[-1]):
            orig = x_clean[:, :, f]  # [B, T]
            proj = x_proj[:, :, f]  # [B, T]

            orig_mean = orig.mean(dim=1, keepdim=True)  # [B, 1]
            orig_std = orig.std(dim=1, keepdim=True)  # [B, 1]
            proj_mean = proj.mean(dim=1, keepdim=True)
            proj_std = proj.std(dim=1, keepdim=True).clamp(min=1e-8)

            # Standardize then rescale to match original moments
            proj_normed = (proj - proj_mean) / proj_std
            proj_matched = proj_normed * orig_std + orig_mean
            channels.append(proj_matched.unsqueeze(-1))

        x_proj = torch.cat(channels, dim=-1)

        # Re-apply Lp bounds (moment matching may violate epsilon)
        x_proj = super(PhysicalConstraint, self).project(x_clean, x_proj)

        return x_proj
