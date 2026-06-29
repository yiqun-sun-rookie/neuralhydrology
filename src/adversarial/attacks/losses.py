"""Loss functions for adversarial attacks.

.. deprecated::
    SUPERSEDED — DO NOT USE FOR PAPER NUMBERS. ``_nse_loss`` below sums squared
    error over ALL timesteps of every window, which is the *full-window* NSE, not
    the official last-step (predict_last_n=1) per-basin NSE that RegressionTester
    reports. This is the exact bug that inflated the old headline ratio to 17.5x.
    The authoritative ID18 pipeline computes damage on the last-step concatenated
    NSE in ``src/adversarial/scripts/coherent_attack.py`` (CoherentBasin). This
    module is retained ONLY to reproduce the pre-ID18 (epoch020/per-window) runs;
    any new robustness number MUST come from coherent_attack.py instead.
"""
from __future__ import annotations

import torch


def _nse_loss(y_pred: torch.Tensor, y_obs: torch.Tensor) -> torch.Tensor:
    """Differentiable NSE (minimize = push NSE down = degrade prediction).

    DEPRECATED: full-window sum over all timesteps — NOT the official last-step
    metric. See module docstring; use coherent_attack.py for authoritative damage.
    """
    ss_res = ((y_obs - y_pred) ** 2).sum()
    ss_tot = ((y_obs - y_obs.mean()) ** 2).sum().clamp(min=1e-10)
    nse = 1.0 - ss_res / ss_tot
    return nse  # We want to MINIMIZE this


def untargeted_nse_loss(y_pred: torch.Tensor, y_obs: torch.Tensor) -> torch.Tensor:
    """Untargeted: minimize NSE over all timesteps."""
    return _nse_loss(y_pred, y_obs)


def targeted_flood_loss(y_pred: torch.Tensor, y_obs: torch.Tensor,
                        quantile: float = 0.9) -> torch.Tensor:
    """Targeted: minimize NSE only on high-flow timesteps."""
    threshold = torch.quantile(y_obs.detach(), quantile)
    mask = (y_obs >= threshold).detach()
    if mask.sum() < 2:
        return untargeted_nse_loss(y_pred, y_obs)
    return _nse_loss(y_pred[mask], y_obs[mask])


def targeted_lowflow_loss(y_pred: torch.Tensor, y_obs: torch.Tensor,
                          quantile: float = 0.1) -> torch.Tensor:
    """Targeted: minimize NSE only on low-flow timesteps."""
    threshold = torch.quantile(y_obs.detach(), quantile)
    mask = (y_obs <= threshold).detach()
    if mask.sum() < 2:
        return untargeted_nse_loss(y_pred, y_obs)
    return _nse_loss(y_pred[mask], y_obs[mask])


def get_loss_fn(target: str):
    """Factory for loss functions."""
    return {
        "untargeted": untargeted_nse_loss,
        "flood": targeted_flood_loss,
        "lowflow": targeted_lowflow_loss,
    }[target]
