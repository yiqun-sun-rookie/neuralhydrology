"""Unit tests for FiLM-LSTM model."""
import torch
import pytest

from neuralhydrology.modelzoo.filmlstm import _FiLMGenerator


class _FakeCfg:
    """Minimal stand-in for neuralhydrology Config in unit tests."""

    def __init__(self, hidden_size=16, film_generator_hidden_size=8):
        self.hidden_size = hidden_size
        self.film_generator_hidden_size = film_generator_hidden_size


def test_film_generator_identity_init():
    """At initialization, generator must output gamma=1 and beta=0 for any input."""
    cfg = _FakeCfg(hidden_size=16)
    S = 24  # static dim
    gen = _FiLMGenerator(cfg, static_size=S)

    # Two different random static inputs
    s1 = torch.randn(4, S)
    s2 = torch.randn(4, S)

    gamma1, beta1 = gen(s1)
    gamma2, beta2 = gen(s2)

    # gamma and beta must not depend on s at init (final-layer weights=0, bias encodes identity)
    assert torch.allclose(gamma1, gamma2, atol=1e-7), "Gamma must be s-independent at init"
    assert torch.allclose(beta1, beta2, atol=1e-7), "Beta must be s-independent at init"

    # gamma ≡ 1, beta ≡ 0
    assert torch.allclose(gamma1, torch.ones_like(gamma1), atol=1e-7), \
        f"Gamma must be ones, got min={gamma1.min()}, max={gamma1.max()}"
    assert torch.allclose(beta1, torch.zeros_like(beta1), atol=1e-7), \
        f"Beta must be zeros, got min={beta1.min()}, max={beta1.max()}"

    # Shape: [batch, 4 * hidden_size]
    assert gamma1.shape == (4, 4 * cfg.hidden_size)
    assert beta1.shape == (4, 4 * cfg.hidden_size)
