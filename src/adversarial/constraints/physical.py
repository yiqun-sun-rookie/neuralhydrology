from __future__ import annotations

from typing import List

import torch

from .lp_norm import LpConstraint


# Physical bounds in REAL (unnormalized) space
_PHYSICAL_BOUNDS = {
    "prcp(mm/day)": (0.0, 500.0),
    "srad(W/m2)": (0.0, 1361.0),  # solar constant; old 600 clamped CLEAN Maurer SRAD (max ~742) -> moved clean data
    "tmax(C)": (-50.0, 60.0),
    "tmin(C)": (-60.0, 50.0),
    "vp(Pa)": (0.0, 10000.0),
}
# F1: case-insensitive lookup — dynamic_inputs may be capitalized (Maurer: PRCP(mm/day),
# Tmin(C), ...) while the dict keys carry mixed-case unit chars (srad(W/m2), tmax(C)).
# A plain feat.lower() would only rescue PRCP; casefold BOTH sides matches all 5.
_PHYSICAL_BOUNDS_CF = {k.casefold(): v for k, v in _PHYSICAL_BOUNDS.items()}


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
            if feat.casefold() in _PHYSICAL_BOUNDS_CF:
                lo, hi = _PHYSICAL_BOUNDS_CF[feat.casefold()]
                lo_norm = (lo - center[i]) / scale[i].clamp(min=1e-8)
                hi_norm = (hi - center[i]) / scale[i].clamp(min=1e-8)
                ch = ch.clamp(lo_norm.item(), hi_norm.item())
            channels.append(ch)

        # Re-enforce the eps ball after the physical clamp (eps is the hard threat-model
        # bound; the physical clip can otherwise push delta beyond eps). Mirrors statistical.
        return super().project(x_clean, torch.cat(channels, dim=-1))
