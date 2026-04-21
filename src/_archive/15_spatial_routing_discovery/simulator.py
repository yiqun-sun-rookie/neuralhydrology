"""Cellular automaton water flow simulator (D8-based, vectorized)."""

from typing import List, Optional

import numpy as np

from spatial_routing_discovery.terrain import compute_d8_flow, _D8_DR, _D8_DC


class WaterSimulator:
    """Simulates surface water flow over a DEM using pre-computed D8 routing."""

    def __init__(self, dem: np.ndarray, flow_fraction: float = 0.5):
        self.dem = dem.astype(np.float32)
        self.flow_fraction = flow_fraction
        self.water = np.zeros_like(dem, dtype=np.float32)
        self.outlet_loss = 0.0
        self.nrows, self.ncols = dem.shape

        # Pre-compute flow targets for vectorized step
        flow_dir, _ = compute_d8_flow(dem)
        self._target_r = np.zeros_like(flow_dir, dtype=np.int32)
        self._target_c = np.zeros_like(flow_dir, dtype=np.int32)
        self._has_target = flow_dir >= 0

        for r in range(self.nrows):
            for c in range(self.ncols):
                d = flow_dir[r, c]
                if d >= 0:
                    self._target_r[r, c] = r + _D8_DR[d]
                    self._target_c[r, c] = c + _D8_DC[d]

    def add_rainfall(self, rainfall: np.ndarray):
        self.water += rainfall.astype(np.float32)

    def step(self):
        transfer = np.where(self._has_target, self.water * self.flow_fraction, 0.0).astype(np.float32)
        self.water -= transfer

        inflow = np.zeros_like(self.water)
        np.add.at(inflow, (self._target_r[self._has_target], self._target_c[self._has_target]),
                  transfer[self._has_target])

        # Track water that flows into outlet/boundary cells (cells with no target).
        # These cells will be zeroed out, so any inflow to them is lost from the grid.
        no_target = ~self._has_target
        boundary_inflow = inflow[no_target].sum()
        self.outlet_loss += float(boundary_inflow)

        # Also track the water remaining in no-target cells (they had no outflow
        # via transfer since _has_target is False, but they still hold water from
        # previous steps or rainfall).  We zero them out, so that water is lost too.
        self.outlet_loss += float(self.water[no_target].sum())

        self.water += inflow
        self.water[no_target] = 0.0

    def run_sequence(self, rainfall_per_step: np.ndarray, n_steps: int,
                     rainfall_steps: Optional[int] = None) -> List[np.ndarray]:
        if rainfall_steps is None:
            rainfall_steps = n_steps
        snapshots = []
        for t in range(n_steps):
            if t < rainfall_steps:
                self.add_rainfall(rainfall_per_step)
            self.step()
            snapshots.append(self.water.copy())
        return snapshots
