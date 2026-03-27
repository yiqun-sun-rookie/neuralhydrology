"""Tests for CoupledHydroModel (true alternating HBV ↔ LSTM with encoder/decoder)."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import numpy as np
import pytest
import torch
import torch.nn as nn
from scl_hydro.coupled_model import CoupledHydroModel, GatedStateEncoder, StateDecoder

HBV_PARAMS = {
    "t0": 0.0, "k_snow": 2.5, "Smax": 200.0, "Ce": 0.8, "beta": 2.0,
    "split": 0.5, "k_fast": 0.1, "alpha": 2.0, "k_slow": 0.01, "lag_time": 1.0,
}


def _make_model(**kw):
    defaults = dict(n_forcing=3, hidden_size=32, hbv_params=HBV_PARAMS)
    defaults.update(kw)
    return CoupledHydroModel(**defaults)


class TestShapes:
    def test_output_shapes(self):
        B, T = 4, 30
        out = _make_model()(torch.rand(B, T, 3))
        assert out["y_hat"].shape == (B, T, 1)
        assert out["phys_states"].shape == (B, T, 4)
        assert out["step_type"].shape == (T,)

    def test_step_types_alternate(self):
        out = _make_model()(torch.rand(2, 10, 3))
        # stride=2: 0,1,0,1,0,1,...
        expected = torch.tensor([0, 1, 0, 1, 0, 1, 0, 1, 0, 1])
        assert torch.equal(out["step_type"], expected)

    def test_custom_stride(self):
        out = _make_model(stride=3)(torch.rand(2, 9, 3))
        # stride=3: 0,1,1,0,1,1,0,1,1
        expected = torch.tensor([0, 1, 1, 0, 1, 1, 0, 1, 1])
        assert torch.equal(out["step_type"], expected)


class TestEncoderDecoder:
    def test_encoder_shapes(self):
        enc = GatedStateEncoder(n_input=8, hidden_size=32)
        h = torch.zeros(1, 4, 32)
        c = torch.zeros(1, 4, 32)
        h_new, c_new = enc(torch.rand(4, 8), h, c)
        assert h_new.shape == (1, 4, 32)
        assert c_new.shape == (1, 4, 32)

    def test_decoder_shapes(self):
        dec = StateDecoder(32, 4, torch.tensor([64., 30., 3., 12.]),
                           torch.tensor([98., 14.5, 3., 13.3]))
        state, q = dec(torch.rand(4, 32))
        assert state.shape == (4, 4)
        assert q.shape == (4, 1)

    def test_decoder_outputs_non_negative(self):
        dec = StateDecoder(32, 4, torch.tensor([64., 30., 3., 12.]),
                           torch.tensor([98., 14.5, 3., 13.3]))
        state, q = dec(torch.randn(100, 32))
        assert (state >= 0).all()
        assert (q >= 0).all()


class TestGradientFlow:
    def test_grad_flows_through_lstm_steps(self):
        model = _make_model()
        out = model(torch.rand(2, 10, 3))
        # Loss only on LSTM steps (odd)
        lstm_mask = out["step_type"] == 1
        q_lstm = out["y_hat"][:, lstm_mask, :]
        q_lstm.mean().backward()
        assert model.lstm.weight_ih_l0.grad is not None
        # q_head is Sequential; check last Linear layer
        assert model.decoder.q_head[-1].weight.grad is not None

    def test_grad_flows_through_encoder(self):
        model = _make_model()
        out = model(torch.rand(2, 10, 3))
        out["y_hat"].mean().backward()
        # Encoder should get gradients (LSTM steps depend on encoder output)
        assert model.encoder.gate_h.weight.grad is not None

    def test_hbv_params_fixed(self):
        model = _make_model()
        for name, p in model.named_parameters():
            assert "hbv_" not in name


class TestAlternation:
    def test_hbv_steps_produce_valid_q(self):
        """HBV steps should produce non-negative Q."""
        model = _make_model()
        forcing = torch.rand(4, 20, 3)
        forcing[:, :, 0] *= 20
        with torch.no_grad():
            out = model(forcing)
        hbv_mask = out["step_type"] == 0
        assert (out["y_hat"][:, hbv_mask, :] >= 0).all()

    def test_lstm_steps_produce_valid_q(self):
        """LSTM steps should produce non-negative Q (softplus)."""
        model = _make_model()
        with torch.no_grad():
            out = model(torch.rand(4, 20, 3))
        lstm_mask = out["step_type"] == 1
        assert (out["y_hat"][:, lstm_mask, :] >= 0).all()

    def test_states_non_negative_all_steps(self):
        model = _make_model()
        forcing = torch.rand(4, 20, 3)
        forcing[:, :, 0] *= 15
        with torch.no_grad():
            out = model(forcing)
        assert (out["phys_states"] >= 0).all()

    def test_different_init_states_different_output(self):
        model = _make_model()
        f = torch.rand(1, 10, 3)
        with torch.no_grad():
            out1 = model(f, state_init=torch.tensor([[0., 60., 5., 5.]]))
            out2 = model(f, state_init=torch.tensor([[0., 300., 30., 500.]]))
        assert not torch.allclose(out1["y_hat"], out2["y_hat"], atol=1e-3)

    def test_lstm_depends_on_encoder(self):
        """LSTM output should change when encoder changes (proves dependency)."""
        model = _make_model()
        f = torch.rand(1, 10, 3)

        with torch.no_grad():
            out1 = model(f)

            # Scramble encoder weights
            nn.init.normal_(model.encoder.gate_h.weight, std=10.0)
            nn.init.normal_(model.encoder.cand_h.weight, std=10.0)
            out2 = model(f)

        # LSTM steps should differ (even if by small amount)
        lstm_mask = out1["step_type"] == 1
        q1 = out1["y_hat"][:, lstm_mask, :]
        q2 = out2["y_hat"][:, lstm_mask, :]
        assert not torch.equal(q1, q2), \
            "Scrambling encoder should change LSTM output"


class TestTraining:
    def test_loss_decreases(self):
        torch.manual_seed(42)
        model = _make_model(hidden_size=32)
        optimizer = torch.optim.Adam(model.parameters(), lr=0.005)

        forcing = torch.rand(8, 20, 3)
        forcing[:, :, 0] *= 10
        target = forcing[:, :, 0:1] * 0.3 + 0.5

        losses = []
        for _ in range(50):
            out = model(forcing)
            loss = nn.functional.mse_loss(out["y_hat"], target)
            optimizer.zero_grad(); loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            losses.append(loss.item())
        assert np.mean(losses[-10:]) < np.mean(losses[:10])
