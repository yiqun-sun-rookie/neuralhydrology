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
