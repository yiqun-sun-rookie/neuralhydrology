import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from spatial_routing_discovery.terrain import generate_dem, compute_d8_flow


class TestGenerateDem:
    def test_output_shape(self):
        dem = generate_dem(size=64, seed=42)
        assert dem.shape == (64, 64)

    def test_dtype_float32(self):
        dem = generate_dem(size=64, seed=42)
        assert dem.dtype == np.float32

    def test_has_single_outlet(self):
        dem = generate_dem(size=64, seed=42)
        boundary = np.concatenate([dem[0, :], dem[-1, :], dem[:, 0], dem[:, -1]])
        min_val = boundary.min()
        assert np.sum(boundary == min_val) == 1

    def test_interior_higher_than_outlet(self):
        dem = generate_dem(size=64, seed=42)
        boundary = np.concatenate([dem[0, :], dem[-1, :], dem[:, 0], dem[:, -1]])
        outlet_elev = boundary.min()
        assert dem[1:-1, 1:-1].min() > outlet_elev

    def test_reproducible_with_seed(self):
        dem1 = generate_dem(size=64, seed=42)
        dem2 = generate_dem(size=64, seed=42)
        np.testing.assert_array_equal(dem1, dem2)

    def test_different_seeds_differ(self):
        dem1 = generate_dem(size=64, seed=42)
        dem2 = generate_dem(size=64, seed=99)
        assert not np.array_equal(dem1, dem2)


class TestComputeD8Flow:
    def test_flow_direction_shape(self):
        dem = generate_dem(size=32, seed=42)
        flow_dir, flow_acc = compute_d8_flow(dem)
        assert flow_dir.shape == dem.shape
        assert flow_acc.shape == dem.shape

    def test_flow_direction_values(self):
        dem = generate_dem(size=32, seed=42)
        flow_dir, _ = compute_d8_flow(dem)
        valid_dirs = set(range(-1, 8))
        assert set(np.unique(flow_dir)).issubset(valid_dirs)

    def test_flow_accumulation_positive(self):
        dem = generate_dem(size=32, seed=42)
        _, flow_acc = compute_d8_flow(dem)
        assert flow_acc.min() >= 1

    def test_outlet_has_max_accumulation(self):
        dem = generate_dem(size=32, seed=42)
        _, flow_acc = compute_d8_flow(dem)
        boundary_coords = []
        n = dem.shape[0]
        for i in range(n):
            boundary_coords.extend([(0, i), (n-1, i), (i, 0), (i, n-1)])
        outlet = min(boundary_coords, key=lambda c: dem[c])
        assert flow_acc[outlet] == flow_acc.max()

    def test_simple_slope(self):
        dem = np.tile(np.arange(4, dtype=np.float32), (4, 1))
        flow_dir, _ = compute_d8_flow(dem)
        for r in range(1, 3):
            for c in range(1, 3):
                assert flow_dir[r, c] == 6, f"Cell ({r},{c}) should flow west"
