"""Unit tests for FiLM-LSTM model."""
from typing import Callable

import torch
import pytest

from neuralhydrology.modelzoo.filmlstm import _FiLMGenerator
from neuralhydrology.modelzoo.filmlstm import FiLMLSTM
from test import Fixture


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


def test_filmlstm_forward_shape_and_identity(get_config: Fixture[Callable[[str], dict]]):
    """At init, FiLMLSTM output must not depend on static input (FiLM is identity at init)."""
    config = get_config('daily_regression')
    config.update_config({
        'dataset': 'camels_us',
        'data_dir': config.data_dir / 'camels_us',
        'target_variables': ['QObs(mm/d)'],
        'forcings': 'daymet',
        'dynamic_inputs': ['prcp(mm/day)', 'tmax(C)'],
        'static_attributes': ['elev_mean', 'slope_mean', 'area_gages2'],
        'model': 'filmlstm',
    })

    model = FiLMLSTM(config)
    model.eval()

    # Two different static inputs, same dynamic
    x_d = {k: torch.rand((config.batch_size, 50, 1)) for k in config.dynamic_inputs}
    x_s_1 = torch.rand((config.batch_size, len(config.static_attributes)))
    x_s_2 = torch.rand((config.batch_size, len(config.static_attributes)))

    with torch.no_grad():
        out_1 = model({'x_d': x_d, 'x_s': x_s_1})
        out_2 = model({'x_d': x_d, 'x_s': x_s_2})

    # Shape check
    assert out_1['y_hat'].shape == (config.batch_size, 50, 1)
    assert out_1['h_n'].shape == (config.batch_size, 50, config.hidden_size)
    assert out_1['c_n'].shape == (config.batch_size, 50, config.hidden_size)

    # Identity init: outputs must be identical across different static inputs
    assert torch.allclose(out_1['y_hat'], out_2['y_hat'], atol=1e-6), \
        "At init, FiLMLSTM output must not depend on static input (gamma=1, beta=0)"


def test_filmlstm_gradient_flow(get_config: Fixture[Callable[[str], dict]]):
    """All parameters (film generator + LSTM core + head) must receive non-None gradients."""
    config = get_config('daily_regression')
    config.update_config({
        'dataset': 'camels_us',
        'data_dir': config.data_dir / 'camels_us',
        'target_variables': ['QObs(mm/d)'],
        'forcings': 'daymet',
        'dynamic_inputs': ['prcp(mm/day)', 'tmax(C)'],
        'static_attributes': ['elev_mean', 'slope_mean', 'area_gages2'],
        'model': 'filmlstm',
    })

    model = FiLMLSTM(config)

    x_d = {k: torch.rand((config.batch_size, 50, 1)) for k in config.dynamic_inputs}
    x_s = torch.rand((config.batch_size, len(config.static_attributes)))

    out = model({'x_d': x_d, 'x_s': x_s})
    loss = out['y_hat'].sum()
    loss.backward()

    missing_grads = [n for n, p in model.named_parameters() if p.requires_grad and p.grad is None]
    assert not missing_grads, f"Parameters without gradients: {missing_grads}"


def test_film_generator_unbounded_mode_identity_and_range():
    """bounded=False: still identity at init, but gamma can leave (0, 2) — negative and >2."""
    cfg = _FakeCfg(hidden_size=16)
    S = 24
    gen = _FiLMGenerator(cfg, static_size=S, bounded=False)

    gamma, beta = gen(torch.randn(4, S))
    assert torch.allclose(gamma, torch.ones_like(gamma), atol=1e-7), "Unbounded mode must still init to gamma=1"
    assert torch.allclose(beta, torch.zeros_like(beta), atol=1e-7)

    # Force raw = bias (final weights are zero) spanning [-4, 4] -> gamma in [-3, 5]
    gen.mlp_gamma[-1].bias.data = torch.linspace(-4.0, 4.0, 4 * cfg.hidden_size)
    gamma, _ = gen(torch.randn(4, S))
    assert (gamma < 0).any(), "Unbounded mode must allow negative gamma (Perez et al. 2018)"
    assert (gamma > 2).any(), "Unbounded mode must allow gamma > 2"

    # Bounded mode with the same bias stays inside (0, 2)
    gen_b = _FiLMGenerator(cfg, static_size=S, bounded=True)
    gen_b.mlp_gamma[-1].bias.data = torch.linspace(-4.0, 4.0, 4 * cfg.hidden_size)
    gamma_b, _ = gen_b(torch.randn(4, S))
    assert (gamma_b > 0).all() and (gamma_b < 2).all()


def test_filmlstm_input_site_identity_and_shape(get_config: Fixture[Callable[[str], dict]]):
    """film_site='input': identity at init (output independent of statics), same output shapes."""
    config = get_config('daily_regression')
    config.update_config({
        'dataset': 'camels_us',
        'data_dir': config.data_dir / 'camels_us',
        'target_variables': ['QObs(mm/d)'],
        'forcings': 'daymet',
        'dynamic_inputs': ['prcp(mm/day)', 'tmax(C)'],
        'static_attributes': ['elev_mean', 'slope_mean', 'area_gages2'],
        'model': 'filmlstm',
        'film_site': 'input',
    })

    model = FiLMLSTM(config)
    model.eval()

    x_d = {k: torch.rand((config.batch_size, 50, 1)) for k in config.dynamic_inputs}
    x_s_1 = torch.rand((config.batch_size, len(config.static_attributes)))
    x_s_2 = torch.rand((config.batch_size, len(config.static_attributes)))

    with torch.no_grad():
        out_1 = model({'x_d': x_d, 'x_s': x_s_1})
        out_2 = model({'x_d': x_d, 'x_s': x_s_2})

    assert out_1['y_hat'].shape == (config.batch_size, 50, 1)
    assert torch.allclose(out_1['y_hat'], out_2['y_hat'], atol=1e-6), \
        "At init, input-site FiLMLSTM output must not depend on static input"


def test_filmlstm_input_site_stable_gradients_with_extreme_gamma(get_config: Fixture[Callable[[str], dict]]):
    """film_site='input' with gamma forced to [-3, 5] over a 365-step sequence: gradients stay finite.

    This is the stability property that makes the unbounded gamma safe: gamma scales only the input
    projection, never the recurrent term, so it cannot compound through the 365-step recurrence."""
    config = get_config('daily_regression')
    config.update_config({
        'dataset': 'camels_us',
        'data_dir': config.data_dir / 'camels_us',
        'target_variables': ['QObs(mm/d)'],
        'forcings': 'daymet',
        'dynamic_inputs': ['prcp(mm/day)', 'tmax(C)'],
        'static_attributes': ['elev_mean', 'slope_mean', 'area_gages2'],
        'model': 'filmlstm',
        'film_site': 'input',
    })

    model = FiLMLSTM(config)
    H = config.hidden_size
    # Final weights are zero, so gamma = 1 + bias exactly: force gamma to span [-3, 5]
    model.film_generator.mlp_gamma[-1].bias.data = torch.linspace(-4.0, 4.0, 4 * H)
    model.film_generator.mlp_beta[-1].bias.data = torch.linspace(-2.0, 2.0, 4 * H)

    x_d = {k: torch.rand((2, 365, 1)) for k in config.dynamic_inputs}
    x_s = torch.rand((2, len(config.static_attributes)))

    out = model({'x_d': x_d, 'x_s': x_s})
    assert torch.isfinite(out['y_hat']).all(), "Forward must stay finite under extreme gamma"

    out['y_hat'].mean().backward()
    for name, p in model.named_parameters():
        if p.requires_grad and p.grad is not None:
            assert torch.isfinite(p.grad).all(), f"Non-finite gradient in {name} under extreme gamma"


def test_analyze_film_poc_verdict_on_synthetic_data(tmp_path: Fixture):
    """Analysis script must apply threshold B correctly on synthetic NSE tables."""
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src' / 'static_falsification' / 'scripts'))
    from analyze_film_poc import compute_verdict

    # Simulate a clear PASS: FiLM real = 0.72, EA real = 0.68, shuffle cases much lower
    per_run_nse = {
        ('ealstm',   'real',    0): 0.68, ('ealstm',   'real',    1): 0.68,
        ('filmlstm', 'real',    0): 0.72, ('filmlstm', 'real',    1): 0.72,
        ('ealstm',   'shuffle', 0): 0.60, ('ealstm',   'shuffle', 1): 0.60,
        ('filmlstm', 'shuffle', 0): 0.62, ('filmlstm', 'shuffle', 1): 0.62,
    }
    verdict = compute_verdict(per_run_nse, threshold='B')
    assert verdict['go'] is True
    assert verdict['delta_arch'] == pytest.approx(0.04, abs=1e-6)
    assert verdict['delta_phys_film'] == pytest.approx(0.10, abs=1e-6)
    assert verdict['delta_phys_ea'] == pytest.approx(0.08, abs=1e-6)

    # Simulate a clear FAIL: FiLM slightly worse than EA
    per_run_nse_fail = {
        ('ealstm',   'real',    0): 0.68, ('ealstm',   'real',    1): 0.68,
        ('filmlstm', 'real',    0): 0.67, ('filmlstm', 'real',    1): 0.67,
        ('ealstm',   'shuffle', 0): 0.60, ('ealstm',   'shuffle', 1): 0.60,
        ('filmlstm', 'shuffle', 0): 0.60, ('filmlstm', 'shuffle', 1): 0.60,
    }
    verdict_fail = compute_verdict(per_run_nse_fail, threshold='B')
    assert verdict_fail['go'] is False
