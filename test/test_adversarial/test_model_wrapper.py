import pytest
import torch


@pytest.fixture
def wrapper():
    """Load the real CudaLSTM wrapper. Skip if checkpoint not available."""
    from src.adversarial.model_wrapper import CudaLSTMWrapper
    from pathlib import Path

    run_dir = Path(r"G:\github\pycharm\projects\neuralhydrology\runs\05_full_531_basins_smoke_v2_2026_0217_1632_ep1")
    if not run_dir.exists():
        pytest.skip("neuralhydrology run_dir not found")
    return CudaLSTMWrapper(run_dir=run_dir, device="cpu")


class TestCudaLSTMWrapper:

    def test_forward_shape(self, wrapper):
        """Forward pass returns correct shape."""
        B, T = 2, 365
        x_d = torch.randn(B, T, wrapper.n_dynamic)
        x_s = torch.randn(B, wrapper.n_static)
        y_hat = wrapper.forward(x_d, x_s)
        assert y_hat.shape == (B, T, 1)

    def test_forward_requires_grad(self, wrapper):
        """Output has grad_fn when input requires_grad (needed for attacks)."""
        B, T = 2, 365
        x_d = torch.randn(B, T, wrapper.n_dynamic, requires_grad=True)
        x_s = torch.randn(B, wrapper.n_static)
        y_hat = wrapper.forward(x_d, x_s)
        assert y_hat.requires_grad

    def test_feature_names(self, wrapper):
        """Wrapper exposes feature names and indices."""
        assert wrapper.n_dynamic > 0
        assert len(wrapper.dynamic_features) == wrapper.n_dynamic

    def test_scaler(self, wrapper):
        """Wrapper exposes scaler for denormalization."""
        scaler = wrapper.get_scaler()
        assert isinstance(scaler, dict)
