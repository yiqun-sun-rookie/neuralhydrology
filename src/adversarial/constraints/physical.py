from __future__ import annotations

from typing import List

import torch

from .lp_norm import LpConstraint


# Physical bounds in REAL (unnormalized) space
_PHYSICAL_BOUNDS = {
    "prcp(mm/day)": (0.0, 500.0),
    "srad(W/m2)": (0.0, 600.0),
    "tmax(C)": (-50.0, 60.0),
    "tmin(C)": (-60.0, 50.0),
    "vp(Pa)": (0.0, 10000.0),
}


class PhysicalConstraint(LpConstraint):
    """Lp + physical feasibility (non-negative precip, T range, etc.)."""

    def __init__(self, epsilon: float, feature_names: List[str],
                 scaler_center: torch.Tensor, scaler_scale: torch.Tensor,
                 norm: str = "linf"):
        super().__init__(epsilon, norm)
        self.feature_names = feature_names
        self._scaler_center = scaler_center
        self._scaler_scale = scaler_scale

    def project(self, x_clean: torch.Tensor, x_adv: torch.Tensor) -> torch.Tensor:
        # First apply Lp projection
        x_proj = super().project(x_clean, x_adv)

        # Then clip to physical bounds in real space (autograd-safe, no inplace ops)
        center = self._scaler_center.to(x_proj.device)
        scale = self._scaler_scale.to(x_proj.device)

        channels = []
        for i, feat in enumerate(self.feature_names):
            ch = x_proj[:, :, i:i+1]
            if feat in _PHYSICAL_BOUNDS:
                lo, hi = _PHYSICAL_BOUNDS[feat]
                lo_norm = (lo - center[i]) / scale[i].clamp(min=1e-8)
                hi_norm = (hi - center[i]) / scale[i].clamp(min=1e-8)
                ch = ch.clamp(lo_norm.item(), hi_norm.item())
            channels.append(ch)

        return torch.cat(channels, dim=-1)
