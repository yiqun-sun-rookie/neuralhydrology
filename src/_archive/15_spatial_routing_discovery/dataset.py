"""Rainfall generation and PyTorch Dataset for routing experiments."""

from typing import List, Tuple

import numpy as np
import torch
from torch.utils.data import Dataset

from spatial_routing_discovery.terrain import generate_dem
from spatial_routing_discovery.simulator import WaterSimulator


def generate_rainfall_event(size: int, event_type: str = "uniform", seed: int = 0,
                            intensity: float = 0.02) -> np.ndarray:
    rng = np.random.RandomState(seed)
    if event_type == "uniform":
        rain = np.full((size, size), intensity, dtype=np.float32)
    elif event_type == "localized":
        y, x = np.mgrid[0:size, 0:size].astype(np.float32)
        cy = rng.uniform(size * 0.2, size * 0.8)
        cx = rng.uniform(size * 0.2, size * 0.8)
        radius = rng.uniform(size * 0.1, size * 0.3)
        dist_sq = (y - cy) ** 2 + (x - cx) ** 2
        rain = intensity * 3.0 * np.exp(-dist_sq / (2 * radius ** 2))
        rain = rain.astype(np.float32)
    elif event_type == "moving":
        y, x = np.mgrid[0:size, 0:size].astype(np.float32)
        angle = rng.uniform(0, np.pi)
        offset = rng.uniform(size * 0.3, size * 0.7)
        proj = x * np.cos(angle) + y * np.sin(angle)
        rain = intensity * 2.0 * np.exp(-((proj - offset) ** 2) / (2 * (size * 0.1) ** 2))
        rain = rain.astype(np.float32)
    else:
        raise ValueError(f"Unknown event_type: {event_type}")
    return rain


class RoutingDataset(Dataset):
    def __init__(self, dem_size: int = 64, dem_seed: int = 42, n_events: int = 50,
                 steps_per_event: int = 20, flow_fraction: float = 0.5):
        self.dem = generate_dem(size=dem_size, seed=dem_seed)
        self.dem_norm = (self.dem - self.dem.min()) / (self.dem.max() - self.dem.min() + 1e-8)
        event_types = ["uniform", "localized", "moving"]
        self.samples: List[Tuple[np.ndarray, np.ndarray, np.ndarray]] = []
        for event_idx in range(n_events):
            etype = event_types[event_idx % len(event_types)]
            rainfall = generate_rainfall_event(size=dem_size, event_type=etype, seed=event_idx * 7 + 1)
            sim = WaterSimulator(self.dem, flow_fraction=flow_fraction)
            snapshots = sim.run_sequence(rainfall_per_step=rainfall, n_steps=steps_per_event)
            for t in range(steps_per_event):
                water_before = snapshots[t - 1] if t > 0 else np.zeros_like(self.dem)
                water_after = snapshots[t]
                self.samples.append((water_before, rainfall, water_after))

    def __len__(self) -> int:
        return len(self.samples)

    def __getitem__(self, idx: int) -> Tuple[torch.Tensor, torch.Tensor]:
        water_before, rainfall, water_after = self.samples[idx]
        x = np.stack([self.dem_norm, water_before, rainfall], axis=0)
        y = water_after[np.newaxis, ...]
        return torch.from_numpy(x).float(), torch.from_numpy(y).float()
