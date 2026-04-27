import pytest
import torch
from pathlib import Path
from types import SimpleNamespace


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

    def test_explicit_epoch_loads_requested_checkpoint(self, monkeypatch, tmp_path):
        """Wrapper should load the requested checkpoint instead of the latest one."""
        from src.adversarial import model_wrapper as mw

        run_dir = tmp_path / "run"
        run_dir.mkdir()
        (run_dir / "config.yml").write_text("dummy: true\n", encoding="utf-8")
        (run_dir / "model_epoch020.pt").write_bytes(b"20")
        (run_dir / "model_epoch030.pt").write_bytes(b"30")

        loaded = {}

        class DummyModel:
            def to(self, device):
                return self

            def load_state_dict(self, state):
                loaded["state"] = state

            def eval(self):
                loaded["eval_called"] = True

        monkeypatch.setattr(
            mw,
            "Config",
            lambda _: SimpleNamespace(dynamic_inputs=["prcp(mm/day)"], static_attributes=[]),
        )
        monkeypatch.setattr(mw, "get_model", lambda cfg: DummyModel())
        monkeypatch.setattr(mw, "load_scaler", lambda _: {})

        def fake_torch_load(path, map_location=None, weights_only=None):
            loaded["path"] = Path(path)
            return {"checkpoint": loaded["path"].name}

        monkeypatch.setattr(mw.torch, "load", fake_torch_load)

        wrapper = mw.CudaLSTMWrapper(run_dir=run_dir, device="cpu", epoch=20)

        assert loaded["path"].name == "model_epoch020.pt"
        assert loaded["state"]["checkpoint"] == "model_epoch020.pt"
        assert wrapper.weight_file.name == "model_epoch020.pt"
