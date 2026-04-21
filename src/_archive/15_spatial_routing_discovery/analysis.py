"""Analysis tools for evaluating whether CNN learns spatial routing."""

from typing import List

import numpy as np
import torch

from spatial_routing_discovery.models import RoutingCNN, get_feature_maps


def correlation_with_drainage(feature_map: np.ndarray, flow_acc: np.ndarray) -> float:
    fm_flat = feature_map.flatten().astype(np.float64)
    fa_flat = flow_acc.flatten().astype(np.float64)
    fm_centered = fm_flat - fm_flat.mean()
    fa_centered = fa_flat - fa_flat.mean()
    numer = (fm_centered * fa_centered).sum()
    denom = np.sqrt((fm_centered ** 2).sum() * (fa_centered ** 2).sum())
    if denom < 1e-12:
        return 0.0
    return float(numer / denom)


def dynamic_response_score(model: RoutingCNN, dem: torch.Tensor,
                           rainfall_a: torch.Tensor, rainfall_b: torch.Tensor) -> float:
    water = torch.zeros_like(dem)
    x_a = torch.cat([dem, water, rainfall_a], dim=1)
    x_b = torch.cat([dem, water, rainfall_b], dim=1)
    with torch.no_grad():
        fm_a = get_feature_maps(model, x_a)
        fm_b = get_feature_maps(model, x_b)
    distances = []
    for fa, fb in zip(fm_a, fm_b):
        dist = torch.norm(fa - fb).item()
        distances.append(dist)
    return float(np.mean(distances))


def depth_routing_scores(model: RoutingCNN, x: torch.Tensor,
                         flow_acc: np.ndarray) -> List[float]:
    with torch.no_grad():
        fmaps = get_feature_maps(model, x)
    scores = []
    for fm in fmaps:
        mean_activation = fm[0].mean(dim=0).cpu().numpy()
        corr = correlation_with_drainage(mean_activation, flow_acc)
        scores.append(corr)
    return scores
