import sys
from pathlib import Path

import pytest
import torch

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from spatial_routing_discovery.models import RoutingCNN, get_feature_maps


class TestRoutingCNN:
    @pytest.mark.parametrize("depth", [2, 4, 8])
    def test_output_shape(self, depth):
        model = RoutingCNN(depth=depth, in_channels=3, hidden_channels=32)
        x = torch.randn(2, 3, 64, 64)
        y = model(x)
        assert y.shape == (2, 1, 64, 64)

    @pytest.mark.parametrize("depth", [2, 4, 8])
    def test_output_non_negative(self, depth):
        model = RoutingCNN(depth=depth, in_channels=3, hidden_channels=32)
        x = torch.randn(2, 3, 64, 64)
        y = model(x)
        assert y.min() >= 0.0

    def test_different_depths_different_params(self):
        m2 = RoutingCNN(depth=2, hidden_channels=32)
        m8 = RoutingCNN(depth=8, hidden_channels=32)
        p2 = sum(p.numel() for p in m2.parameters())
        p8 = sum(p.numel() for p in m8.parameters())
        assert p8 > p2

    def test_small_grid(self):
        model = RoutingCNN(depth=4, in_channels=3, hidden_channels=16)
        x = torch.randn(1, 3, 16, 16)
        y = model(x)
        assert y.shape == (1, 1, 16, 16)


class TestGetFeatureMaps:
    def test_returns_all_layers(self):
        model = RoutingCNN(depth=4, hidden_channels=32)
        x = torch.randn(1, 3, 64, 64)
        fmaps = get_feature_maps(model, x)
        assert len(fmaps) == 4

    def test_feature_map_shapes(self):
        model = RoutingCNN(depth=4, hidden_channels=32)
        x = torch.randn(1, 3, 64, 64)
        fmaps = get_feature_maps(model, x)
        for fm in fmaps:
            assert fm.shape[0] == 1
            assert fm.shape[2] == 64
            assert fm.shape[3] == 64

    def test_feature_maps_differ_with_input(self):
        model = RoutingCNN(depth=4, hidden_channels=32)
        x1 = torch.randn(1, 3, 64, 64)
        x2 = torch.randn(1, 3, 64, 64)
        fm1 = get_feature_maps(model, x1)
        fm2 = get_feature_maps(model, x2)
        assert not torch.equal(fm1[0], fm2[0])
