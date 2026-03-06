"""Adversarial attack evaluation metrics."""
from __future__ import annotations

import torch
from scipy import stats


def compute_nse(y_obs: torch.Tensor, y_pred: torch.Tensor) -> float:
    """Nash-Sutcliffe Efficiency."""
    ss_res = ((y_obs - y_pred) ** 2).sum()
    ss_tot = ((y_obs - y_obs.mean()) ** 2).sum()
    return float(1.0 - ss_res / ss_tot.clamp(min=1e-10))


def compute_kge(y_obs: torch.Tensor, y_pred: torch.Tensor) -> float:
    """Kling-Gupta Efficiency."""
    r = float(torch.corrcoef(torch.stack([y_obs.flatten(), y_pred.flatten()]))[0, 1])
    alpha = float(y_pred.std() / y_obs.std().clamp(min=1e-10))
    beta = float(y_pred.mean() / y_obs.mean().clamp(min=1e-10))
    return float(1.0 - ((r - 1) ** 2 + (alpha - 1) ** 2 + (beta - 1) ** 2) ** 0.5)


def delta_nse(y_obs: torch.Tensor, y_clean: torch.Tensor,
              y_adv: torch.Tensor) -> float:
    """Change in NSE: NSE(adv) - NSE(clean). Negative = attack succeeded."""
    return compute_nse(y_obs, y_adv) - compute_nse(y_obs, y_clean)


def attack_success_rate(nse_values: torch.Tensor, threshold: float = 0.0) -> float:
    """Fraction of basins where NSE falls below threshold."""
    return float((nse_values < threshold).float().mean())


def detectability_ks(x_clean: torch.Tensor, x_adv: torch.Tensor) -> float:
    """KS-test p-value between clean and adversarial input distributions."""
    result = stats.ks_2samp(
        x_clean.detach().cpu().numpy().flatten(),
        x_adv.detach().cpu().numpy().flatten(),
    )
    return float(result.pvalue)


def peak_error(y_obs: torch.Tensor, y_pred: torch.Tensor,
               quantile: float = 0.9) -> float:
    """Mean relative error on peaks above given quantile."""
    threshold = torch.quantile(y_obs, quantile)
    mask = y_obs >= threshold
    if mask.sum() == 0:
        return 0.0
    obs_peak = y_obs[mask]
    pred_peak = y_pred[mask]
    return float(((obs_peak - pred_peak).abs() / obs_peak.clamp(min=1e-6)).mean())
