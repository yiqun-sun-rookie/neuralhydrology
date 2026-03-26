"""Tests for DifferentiableHBV: consistency with NumPy HBV + gradient flow."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import numpy as np
import pytest
import torch

from scl_hydro.hbv_torch import DifferentiableHBV, PARAM_NAMES, PARAM_BOUNDS

# Import NumPy reference
sys.path.insert(0, str(Path(__file__).parent.parent / "src" / "hbv_camels_us_531"))
from hbv_model import simulate_hbv as simulate_hbv_numpy


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def sample_params():
    """A realistic set of HBV parameters."""
    return {
        "t0": 0.0,
        "k_snow": 2.5,
        "Smax": 200.0,
        "Ce": 0.8,
        "beta": 2.0,
        "split": 0.5,
        "k_fast": 0.1,
        "alpha": 2.0,
        "k_slow": 0.01,
        "lag_time": 3.0,
    }


@pytest.fixture
def sample_forcing():
    """365-day synthetic forcing (deterministic seed)."""
    rng = np.random.RandomState(42)
    T = 365
    rain = rng.exponential(3.0, T).astype(np.float64)
    pet = (2.0 + 1.5 * np.sin(np.linspace(0, 2 * np.pi, T))).astype(np.float64)
    temp = (10.0 + 12.0 * np.sin(np.linspace(-np.pi / 2, 3 * np.pi / 2, T))
            + rng.normal(0, 2, T)).astype(np.float64)
    return rain, pet, temp


@pytest.fixture
def sample_initial_state():
    return {"S_snow": 0.0, "S_soil": 60.0, "S_fast": 5.0, "S_slow": 5.0}


# ---------------------------------------------------------------------------
# Core: NumPy vs PyTorch consistency
# ---------------------------------------------------------------------------

class TestConsistency:
    """Verify PyTorch HBV matches NumPy HBV numerically."""

    def test_q_raw_matches_numpy(self, sample_params, sample_forcing, sample_initial_state):
        """Discharge before lag should match within float32 tolerance."""
        rain, pet, temp = sample_forcing
        T = len(rain)

        # --- NumPy reference (no lag for comparison: set lag_time=1) ---
        params_nolag = {**sample_params, "lag_time": 1.0}
        q_np, final_np = simulate_hbv_numpy(rain, pet, temp, params_nolag,
                                            initial_state=sample_initial_state)

        # --- PyTorch ---
        model = DifferentiableHBV()
        forcing_t = torch.tensor(
            np.stack([rain, pet, temp], axis=-1)[np.newaxis],  # [1, T, 3]
            dtype=torch.float32,
        )
        params_t = model.dict_from_values(params_nolag)
        state_init = torch.tensor(
            [[sample_initial_state["S_snow"], sample_initial_state["S_soil"],
              sample_initial_state["S_fast"], sample_initial_state["S_slow"]]],
            dtype=torch.float32,
        )

        with torch.no_grad():
            q_sim, q_raw, states = model(forcing_t, params_t, state_init)

        q_torch = q_raw[0, :, 0].numpy()

        # With lag_time=1, q_sim == q_raw (single-element kernel)
        np.testing.assert_allclose(q_torch, q_np.astype(np.float32), rtol=1e-4, atol=1e-5,
                                   err_msg="q_raw mismatch between NumPy and PyTorch")

    def test_states_match_numpy(self, sample_params, sample_forcing, sample_initial_state):
        """Final states should match within float32 tolerance."""
        rain, pet, temp = sample_forcing

        params_nolag = {**sample_params, "lag_time": 1.0}
        _, final_np = simulate_hbv_numpy(rain, pet, temp, params_nolag,
                                         initial_state=sample_initial_state)

        model = DifferentiableHBV()
        forcing_t = torch.tensor(
            np.stack([rain, pet, temp], axis=-1)[np.newaxis],
            dtype=torch.float32,
        )
        params_t = model.dict_from_values(params_nolag)
        state_init = torch.tensor(
            [[sample_initial_state["S_snow"], sample_initial_state["S_soil"],
              sample_initial_state["S_fast"], sample_initial_state["S_slow"]]],
            dtype=torch.float32,
        )

        with torch.no_grad():
            _, _, states = model(forcing_t, params_t, state_init)

        final_torch = states[0, -1, :].numpy()
        final_np_arr = np.array([final_np["S_snow"], final_np["S_soil"],
                                 final_np["S_fast"], final_np["S_slow"]], dtype=np.float32)

        np.testing.assert_allclose(final_torch, final_np_arr, rtol=1e-3, atol=1e-3,
                                   err_msg="Final states mismatch")

    def test_q_with_lag_matches_numpy(self, sample_params, sample_forcing, sample_initial_state):
        """Full output (with lag) should match NumPy."""
        rain, pet, temp = sample_forcing

        q_np, _ = simulate_hbv_numpy(rain, pet, temp, sample_params,
                                     initial_state=sample_initial_state)

        model = DifferentiableHBV()
        forcing_t = torch.tensor(
            np.stack([rain, pet, temp], axis=-1)[np.newaxis],
            dtype=torch.float32,
        )
        params_t = model.dict_from_values(sample_params)
        state_init = torch.tensor(
            [[sample_initial_state["S_snow"], sample_initial_state["S_soil"],
              sample_initial_state["S_fast"], sample_initial_state["S_slow"]]],
            dtype=torch.float32,
        )

        with torch.no_grad():
            q_sim, _, _ = model(forcing_t, params_t, state_init)

        q_torch = q_sim[0, :, 0].numpy()
        np.testing.assert_allclose(q_torch, q_np.astype(np.float32), rtol=1e-3, atol=1e-3,
                                   err_msg="q_sim with lag mismatch")

    @pytest.mark.parametrize("param_set", [
        {"t0": -2.0, "k_snow": 1.0, "Smax": 100.0, "Ce": 0.5, "beta": 1.5,
         "split": 0.3, "k_fast": 0.05, "alpha": 1.5, "k_slow": 0.005, "lag_time": 1.0},
        {"t0": 2.0, "k_snow": 4.0, "Smax": 400.0, "Ce": 1.2, "beta": 4.0,
         "split": 0.8, "k_fast": 0.3, "alpha": 2.5, "k_slow": 0.08, "lag_time": 1.0},
    ])
    def test_multiple_param_sets(self, param_set, sample_forcing, sample_initial_state):
        """Consistency across diverse parameter combinations."""
        rain, pet, temp = sample_forcing

        q_np, _ = simulate_hbv_numpy(rain, pet, temp, param_set,
                                     initial_state=sample_initial_state)

        model = DifferentiableHBV()
        forcing_t = torch.tensor(
            np.stack([rain, pet, temp], axis=-1)[np.newaxis], dtype=torch.float32)
        params_t = model.dict_from_values(param_set)
        state_init = torch.tensor(
            [[0.0, 60.0, 5.0, 5.0]], dtype=torch.float32)

        with torch.no_grad():
            q_sim, q_raw, _ = model(forcing_t, params_t, state_init)

        q_torch = q_raw[0, :, 0].numpy()
        np.testing.assert_allclose(q_torch, q_np.astype(np.float32), rtol=1e-3, atol=1e-3)


# ---------------------------------------------------------------------------
# Gradient flow
# ---------------------------------------------------------------------------

class TestGradient:
    """Verify gradients flow through the differentiable HBV."""

    def test_gradient_flows_through_params(self):
        """Loss.backward() should produce non-None gradients for raw params."""
        model = DifferentiableHBV()
        B, T = 2, 30

        forcing = torch.rand(B, T, 3)
        forcing[:, :, 0] *= 10  # rain
        forcing[:, :, 1] = 2.0  # pet
        forcing[:, :, 2] = forcing[:, :, 2] * 20 - 5  # temp

        raw_params = torch.randn(B, 10, requires_grad=True)
        params = model.constrain_params(raw_params)
        state_init = torch.tensor([[0.0, 60.0, 5.0, 5.0]] * B)

        q_sim, _, _ = model(forcing, params, state_init)
        loss = q_sim.mean()
        loss.backward()

        assert raw_params.grad is not None
        assert torch.any(raw_params.grad != 0), "Gradients should be non-zero"

    def test_gradient_flows_through_forward_step(self):
        """Single step should be differentiable."""
        model = DifferentiableHBV()
        state = torch.tensor([[0.0, 60.0, 5.0, 5.0]], requires_grad=True)
        rain = torch.tensor([[5.0]])
        pet = torch.tensor([[2.0]])
        temp = torch.tensor([[10.0]])

        params = model.dict_from_values({
            "t0": 0.0, "k_snow": 2.5, "Smax": 200.0, "Ce": 0.8, "beta": 2.0,
            "split": 0.5, "k_fast": 0.1, "alpha": 2.0, "k_slow": 0.01, "lag_time": 3.0,
        })

        state_next, q = model.forward_step(state, rain, pet, temp, params)
        loss = q.sum() + state_next.sum()
        loss.backward()

        assert state.grad is not None


# ---------------------------------------------------------------------------
# Batch support
# ---------------------------------------------------------------------------

class TestBatch:
    """Verify batched execution produces correct per-basin results."""

    def test_batch_equals_sequential(self, sample_params, sample_forcing):
        """Batched forward should equal running each basin individually."""
        rain, pet, temp = sample_forcing
        model = DifferentiableHBV()

        # Create 3-basin batch with slightly different params
        B = 3
        forcing_single = torch.tensor(
            np.stack([rain, pet, temp], axis=-1)[np.newaxis], dtype=torch.float32)
        forcing_batch = forcing_single.repeat(B, 1, 1)

        param_list = []
        for i in range(B):
            p = {**sample_params, "k_fast": 0.05 + 0.1 * i, "lag_time": 1.0}
            param_list.append(p)

        # Sequential
        q_seq = []
        for i in range(B):
            params_t = model.dict_from_values(param_list[i])
            state_init = torch.tensor([[0.0, 60.0, 5.0, 5.0]])
            with torch.no_grad():
                q_sim, _, _ = model(forcing_single, params_t, state_init)
            q_seq.append(q_sim[0])

        # Batched
        params_batch = {}
        for name in PARAM_NAMES:
            vals = torch.tensor([[param_list[i][name]] for i in range(B)], dtype=torch.float32)
            params_batch[name] = vals
        state_batch = torch.tensor([[0.0, 60.0, 5.0, 5.0]] * B)

        with torch.no_grad():
            q_batch, _, _ = model(forcing_batch, params_batch, state_batch)

        for i in range(B):
            np.testing.assert_allclose(
                q_batch[i].numpy(), q_seq[i].numpy(), rtol=1e-5, atol=1e-6,
                err_msg=f"Basin {i} batch vs sequential mismatch")
