import pytest
from pathlib import Path


RUN_DIR = Path(r"G:\github\pycharm\projects\neuralhydrology\runs\05_full_531_basins_smoke_v2_2026_0217_1632_ep1")


class TestAdversarialDataLoader:

    def test_load_basin(self):
        if not RUN_DIR.exists():
            pytest.skip("run_dir not found")

        from src.adversarial.data_loader import load_basin_data

        x_d, x_s, y_obs = load_basin_data(
            run_dir=RUN_DIR,
            basin_id="01013500",
            period="test",
            device="cpu",
        )
        assert x_d.ndim == 3  # [B, T, F]
        assert x_s.ndim == 2  # [B, S]
        assert y_obs.ndim == 3  # [B, T, 1]
