import sys
from pathlib import Path

import numpy as np
import pytest
import torch

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from spatial_routing_discovery.analysis import (
    correlation_with_drainage,
    dynamic_response_score,
    depth_routing_scores,
)
from spatial_routing_discovery.models import RoutingCNN
from spatial_routing_discovery.terrain import generate_dem, compute_d8_flow


class TestCorrelationWithDrainage:
    def test_perfect_correlation(self):
        flow_acc = np.random.rand(32, 32).astype(np.float32)
        feature_map = flow_acc.copy()
        corr = correlation_with_drainage(feature_map, flow_acc)
        assert abs(corr - 1.0) < 1e-5

    def test_random_low_correlation(self):
        rng = np.random.RandomState(42)
        flow_acc = rng.rand(32, 32).astype(np.float32) * 100
        feature_map = rng.rand(32, 32).astype(np.float32)
        corr = correlation_with_drainage(feature_map, flow_acc)
        assert abs(corr) < 0.3

    def test_returns_float(self):
        flow_acc = np.ones((16, 16), dtype=np.float32)
        fm = np.ones((16, 16), dtype=np.float32)
        corr = correlation_with_drainage(fm, flow_acc)
        assert isinstance(corr, float)


class TestDynamicResponseScore:
    def test_same_input_zero_score(self):
        model = RoutingCNN(depth=2, hidden_channels=16)
        model.eval()
        dem = torch.randn(1, 1, 16, 16)
        rain = torch.randn(1, 1, 16, 16)
        score = dynamic_response_score(model, dem, rain, rain)
        assert score < 1e-5

    def test_different_input_positive_score(self):
        model = RoutingCNN(depth=2, hidden_channels=16)
        model.eval()
        dem = torch.randn(1, 1, 16, 16)
        rain_a = torch.randn(1, 1, 16, 16)
        rain_b = torch.randn(1, 1, 16, 16) * 5
        score = dynamic_response_score(model, dem, rain_a, rain_b)
        assert score > 0.0


class TestDepthRoutingScores:
    def test_returns_per_layer_scores(self):
        dem = generate_dem(size=16, seed=42)
        _, flow_acc = compute_d8_flow(dem)
        model = RoutingCNN(depth=4, hidden_channels=16)
        model.eval()
        dem_norm = (dem - dem.min()) / (dem.max() - dem.min() + 1e-8)
        x = torch.zeros(1, 3, 16, 16)
        x[0, 0] = torch.from_numpy(dem_norm)
        x[0, 1] = torch.randn(16, 16) * 0.01
        x[0, 2] = torch.randn(16, 16).abs() * 0.02
        scores = depth_routing_scores(model, x, flow_acc)
        assert len(scores) == 4
        assert all(isinstance(s, float) for s in scores)
