import sys
from pathlib import Path

import numpy as np
import pytest
import torch

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from spatial_routing_discovery.dataset import generate_rainfall_event, RoutingDataset


class TestGenerateRainfallEvent:
    def test_uniform_shape(self):
        rain = generate_rainfall_event(size=32, event_type="uniform", seed=0)
        assert rain.shape == (32, 32)
        assert rain.dtype == np.float32

    def test_localized_has_peak(self):
        rain = generate_rainfall_event(size=32, event_type="localized", seed=0)
        center_val = rain[14:18, 14:18].mean()
        edge_val = rain[0:4, 0:4].mean()
        assert center_val > edge_val

    def test_uniform_is_constant(self):
        rain = generate_rainfall_event(size=32, event_type="uniform", seed=0)
        assert rain.std() < 1e-6

    def test_all_non_negative(self):
        for etype in ["uniform", "localized", "moving"]:
            rain = generate_rainfall_event(size=32, event_type=etype, seed=0)
            assert rain.min() >= 0.0


class TestRoutingDataset:
    @pytest.fixture
    def dataset(self):
        return RoutingDataset(dem_size=16, dem_seed=42, n_events=3, steps_per_event=10, flow_fraction=0.5)

    def test_length(self, dataset):
        assert len(dataset) == 30

    def test_sample_shapes(self, dataset):
        x, y = dataset[0]
        assert x.shape == (3, 16, 16)
        assert y.shape == (1, 16, 16)

    def test_sample_dtype(self, dataset):
        x, y = dataset[0]
        assert x.dtype == torch.float32
        assert y.dtype == torch.float32

    def test_dem_channel_constant(self, dataset):
        x0, _ = dataset[0]
        x1, _ = dataset[1]
        torch.testing.assert_close(x0[0], x1[0])

    def test_different_events_differ(self, dataset):
        x_event0, _ = dataset[0]
        x_event1, _ = dataset[10]
        assert not torch.equal(x_event0[2], x_event1[2])
