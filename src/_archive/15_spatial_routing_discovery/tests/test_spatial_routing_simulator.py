import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from spatial_routing_discovery.terrain import generate_dem
from spatial_routing_discovery.simulator import WaterSimulator


class TestWaterSimulator:
    @pytest.fixture
    def small_dem(self):
        return generate_dem(size=16, seed=42)

    @pytest.fixture
    def sim(self, small_dem):
        return WaterSimulator(small_dem, flow_fraction=0.5)

    def test_initial_water_zero(self, sim):
        assert sim.water.sum() == 0.0

    def test_add_rainfall_uniform(self, sim):
        rainfall = np.ones_like(sim.dem) * 0.1
        sim.add_rainfall(rainfall)
        np.testing.assert_allclose(sim.water.sum(), 0.1 * sim.dem.size, rtol=1e-5)

    def test_step_moves_water_downhill(self, sim):
        high_r, high_c = np.unravel_index(sim.dem[1:-1, 1:-1].argmax(), sim.dem[1:-1, 1:-1].shape)
        high_r += 1
        high_c += 1
        sim.water[high_r, high_c] = 1.0
        sim.step()
        assert sim.water[high_r, high_c] < 1.0

    def test_mass_conservation(self, sim):
        rainfall = np.ones_like(sim.dem) * 0.01
        sim.add_rainfall(rainfall)
        total_added = sim.water.sum()
        for _ in range(5):
            sim.step()
        remaining = sim.water.sum()
        np.testing.assert_allclose(remaining + sim.outlet_loss, total_added, rtol=1e-5)

    def test_run_sequence(self, sim):
        rainfall = np.ones_like(sim.dem) * 0.01
        seq = sim.run_sequence(rainfall_per_step=rainfall, n_steps=10)
        assert len(seq) == 10
        assert seq[0].shape == sim.dem.shape
        assert seq[0].dtype == np.float32

    def test_water_accumulates_in_valley(self, sim):
        rainfall = np.ones_like(sim.dem) * 0.02
        seq = sim.run_sequence(rainfall_per_step=rainfall, n_steps=50)
        final_water = seq[-1]
        from spatial_routing_discovery.terrain import compute_d8_flow
        _, flow_acc = compute_d8_flow(sim.dem)
        threshold = np.percentile(flow_acc, 90)
        channel_mask = flow_acc >= threshold
        ridge_mask = flow_acc <= np.percentile(flow_acc, 10)
        assert final_water[channel_mask].mean() > final_water[ridge_mask].mean()
