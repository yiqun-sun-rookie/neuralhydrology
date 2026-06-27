"""Unit tests for the peak-weighted MSE loss and its config wiring (Gangnan Part 2)."""
import pytest
import torch

from neuralhydrology.utils.config import Config


def _cfg(**overrides):
    base = {"predict_last_n": 1, "target_variables": ["INQ"], "loss": "MSE"}
    base.update(overrides)
    return Config(base, dev_mode=True)


def test_peak_loss_config_defaults():
    cfg = _cfg()
    assert cfg.peak_loss_alpha == 0.0
    assert cfg.peak_loss_threshold == 1.5
    assert cfg.peak_loss_weight_cap is None


def test_peak_loss_config_overrides():
    cfg = _cfg(peak_loss_alpha=2.0, peak_loss_threshold=1.0, peak_loss_weight_cap=5.0)
    assert cfg.peak_loss_alpha == 2.0
    assert cfg.peak_loss_threshold == 1.0
    assert cfg.peak_loss_weight_cap == 5.0


from neuralhydrology.training.loss import MaskedMSELoss, MaskedPeakWeightedMSELoss


def test_alpha_zero_equals_plain_mse():
    cfg = _cfg()
    mse = MaskedMSELoss(cfg)
    peak0 = MaskedPeakWeightedMSELoss(cfg, alpha=0.0, threshold=1.5)
    torch.manual_seed(0)
    y = torch.randn(8, 5, 1)
    y_hat = torch.randn(8, 5, 1)
    y[0, 0, 0] = float("nan")  # exercise the NaN-masking path
    l_mse = mse._get_loss({"y_hat": y_hat}, {"y": y})
    l_peak = peak0._get_loss({"y_hat": y_hat}, {"y": y})
    assert torch.allclose(l_mse, l_peak, atol=1e-6)


def test_peak_error_costs_more_than_baseflow_error():
    # The class must penalize the SAME squared error more when it lands on a peak
    # (y above tau) than on baseflow (y below tau); plain MSE penalizes them equally.
    cfg = _cfg()
    mse = MaskedMSELoss(cfg)
    peak = MaskedPeakWeightedMSELoss(cfg, alpha=2.0, threshold=1.5)
    y = torch.tensor([[[0.0]], [[5.0]]])               # baseflow (w=1) + peak (w=8)
    yhat_peak_err = torch.tensor([[[0.0]], [[3.0]]])   # squared error 4 at the peak
    yhat_base_err = torch.tensor([[[2.0]], [[5.0]]])   # squared error 4 at baseflow
    # plain MSE: identical (same total squared error, equal weights)
    assert torch.allclose(mse._get_loss({"y_hat": yhat_peak_err}, {"y": y}),
                          mse._get_loss({"y_hat": yhat_base_err}, {"y": y}))
    # peak-weighted: peak error costs strictly more than the same baseflow error
    assert peak._get_loss({"y_hat": yhat_peak_err}, {"y": y}).item() > \
           peak._get_loss({"y_hat": yhat_base_err}, {"y": y}).item()


def test_nan_masking_matches_manual():
    cfg = _cfg()
    peak = MaskedPeakWeightedMSELoss(cfg, alpha=1.0, threshold=1.0)
    y = torch.tensor([2.0, float("nan"), 0.0]).reshape(-1, 1, 1)
    y_hat = torch.tensor([1.0, 99.0, 0.5]).reshape(-1, 1, 1)
    w0, w2 = 2.0, 1.0  # 1+1*max(2-1,0)=2 ; 1+1*max(0-1,0)=1
    expected = 0.5 * (w0 * (1.0 - 2.0) ** 2 + w2 * (0.5 - 0.0) ** 2) / (w0 + w2)
    got = peak._get_loss({"y_hat": y_hat}, {"y": y})
    assert got.item() == pytest.approx(expected, rel=1e-6)


def test_gradient_finite_under_extreme_peak():
    cfg = _cfg()
    peak = MaskedPeakWeightedMSELoss(cfg, alpha=2.0, threshold=1.5)
    y = torch.tensor([50.0, 0.0, 1.0]).reshape(-1, 1, 1)   # z=50 extreme
    y_hat = torch.zeros(3, 1, 1, requires_grad=True)
    loss = peak._get_loss({"y_hat": y_hat}, {"y": y})
    loss.backward()
    assert torch.isfinite(loss)
    assert torch.isfinite(y_hat.grad).all()


def test_weight_cap_limits_single_timestep():
    cfg = _cfg()
    capped = MaskedPeakWeightedMSELoss(cfg, alpha=2.0, threshold=1.5, weight_cap=5.0)
    y = torch.tensor([50.0]).reshape(-1, 1, 1)            # uncapped w = 1+2*48.5 = 98
    y_hat = torch.tensor([0.0]).reshape(-1, 1, 1)
    expected = 0.5 * 5.0 * (0.0 - 50.0) ** 2 / 5.0        # cap -> 0.5*2500
    assert capped._get_loss({"y_hat": y_hat}, {"y": y}).item() == pytest.approx(expected, rel=1e-6)
