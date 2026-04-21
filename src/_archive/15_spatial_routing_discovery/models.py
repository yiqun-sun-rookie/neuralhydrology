"""CNN architectures at different depths for spatial routing prediction."""

from typing import List

import torch
import torch.nn as nn


class RoutingCNN(nn.Module):
    def __init__(self, depth: int = 4, in_channels: int = 3, hidden_channels: int = 32):
        super().__init__()
        layers = []
        for i in range(depth):
            ic = in_channels if i == 0 else hidden_channels
            layers.append(nn.Conv2d(ic, hidden_channels, kernel_size=3, padding=1))
            layers.append(nn.ReLU(inplace=True))
        self.features = nn.Sequential(*layers)
        self.head = nn.Conv2d(hidden_channels, 1, kernel_size=1)
        self.out_activation = nn.ReLU()

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        h = self.features(x)
        return self.out_activation(self.head(h))


def get_feature_maps(model: RoutingCNN, x: torch.Tensor) -> List[torch.Tensor]:
    feature_maps = []
    h = x
    for layer in model.features:
        h = layer(h)
        if isinstance(layer, nn.ReLU):
            feature_maps.append(h.detach().clone())
    return feature_maps
