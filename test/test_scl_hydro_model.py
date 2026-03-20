"""Tests for SCL-LSTM model components: ObsEncoder and SCLCudaLSTM."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import pytest
import torch
from scl_hydro.model import ObsEncoder, SCLCudaLSTM


def test_obs_encoder_output_shapes():
    """ObsEncoder should produce (h_0, c_0) with correct shapes."""
    batch_size = 4
    context_len = 30
    n_enc_features = 5  # P, T, humidity, radiation, Q_obs
    enc_hidden = 64
    main_hidden = 256

    encoder = ObsEncoder(
        input_size=n_enc_features,
        enc_hidden_size=enc_hidden,
        main_hidden_size=main_hidden,
    )

    x = torch.randn(batch_size, context_len, n_enc_features)
    h0, c0 = encoder(x)

    # PyTorch LSTM format: (num_layers, batch, hidden)
    assert h0.shape == (1, batch_size, main_hidden)
    assert c0.shape == (1, batch_size, main_hidden)


def test_obs_encoder_gradient_flow():
    """Gradients should flow back through the encoder."""
    encoder = ObsEncoder(input_size=3, enc_hidden_size=16, main_hidden_size=32)
    x = torch.randn(2, 10, 3)
    h0, c0 = encoder(x)
    loss = h0.sum() + c0.sum()
    loss.backward()

    # Check that encoder LSTM weights have gradients
    assert encoder.lstm.weight_ih_l0.grad is not None
    assert encoder.proj_h.weight.grad is not None
    assert encoder.proj_c.weight.grad is not None


def test_scl_cudalstm_forward_shapes():
    """SCLCudaLSTM should output predictions and hidden states."""
    batch = 4
    seg_len = 30
    context_len = 10
    n_main_feat = 3
    n_enc_feat = 4  # main features + Q_obs
    hidden = 32

    model = SCLCudaLSTM(
        n_main_features=n_main_feat,
        n_enc_features=n_enc_feat,
        hidden_size=hidden,
        enc_hidden_size=16,
        n_targets=1,
    )

    predict_x = torch.randn(batch, seg_len, n_main_feat)
    context_x = torch.randn(batch, context_len, n_enc_feat)
    result = model(predict_x, context_x)

    assert result["y_hat"].shape == (batch, seg_len, 1)
    assert result["lstm_output"].shape == (batch, seg_len, hidden)


def test_scl_cudalstm_no_encoder():
    """When context_data is None, should use zero initial state."""
    model = SCLCudaLSTM(
        n_main_features=3,
        n_enc_features=4,
        hidden_size=32,
        enc_hidden_size=16,
        n_targets=1,
    )
    predict_x = torch.randn(2, 20, 3)
    result = model(predict_x, context_data=None)
    assert result["y_hat"].shape == (2, 20, 1)
