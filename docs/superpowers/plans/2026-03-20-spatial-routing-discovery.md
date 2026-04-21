# Spatial Routing Discovery — Can CNNs Learn Water Flow Routing?

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Test whether a CNN can discover spatial water flow routing from DEM + rainfall input without being told the river network topology, and whether its internal features show physically meaningful dynamic responses.

**Architecture:** Synthetic 64x64 DEM with known drainage → cellular automaton water flow simulator generates training data → CNN models at depths 2/4/8 predict next-timestep water depth → analysis compares internal feature maps against known drainage paths under varying rainfall.

**Tech Stack:** PyTorch, NumPy, Matplotlib, no external hydro data

---

## File Structure

```
src/spatial_routing_discovery/
├── __init__.py                 # Package docstring
├── terrain.py                  # Synthetic DEM generation
├── simulator.py                # Cellular automaton water flow (D8)
├── dataset.py                  # PyTorch Dataset wrapping simulated sequences
├── models.py                   # CNN architectures at different depths
├── analysis.py                 # Feature map extraction + routing analysis
└── scripts/
    ├── __init__.py
    ├── run_experiment.py       # End-to-end: generate data → train → analyze
    └── visualize_features.py   # Standalone visualization of trained model internals

test/
├── test_spatial_routing_terrain.py
├── test_spatial_routing_simulator.py
├── test_spatial_routing_dataset.py
├── test_spatial_routing_models.py
└── test_spatial_routing_analysis.py
```

---

### Task 1: Synthetic DEM Generation (`terrain.py`)

**Files:**
- Create: `src/spatial_routing_discovery/__init__.py`
- Create: `src/spatial_routing_discovery/terrain.py`
- Create: `test/test_spatial_routing_terrain.py`

**Context:** Generate a 64x64 synthetic DEM with clear drainage structure. The terrain should have:
- A main valley running diagonally or vertically
- Side ridges creating tributaries that merge into the main valley
- A single outlet point at the edge
- Known ground-truth flow direction grid (D8) and flow accumulation for later validation

The `generate_dem` function returns the DEM array. A separate `compute_d8_flow` function computes the D8 flow direction grid and flow accumulation from any DEM — this serves as ground truth for later probing.

- [ ] **Step 1: Write the failing tests**

```python
# test/test_spatial_routing_terrain.py
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
        """Outlet is the lowest point on the boundary."""
        dem = generate_dem(size=64, seed=42)
        boundary = np.concatenate([
            dem[0, :], dem[-1, :], dem[:, 0], dem[:, -1]
        ])
        # The minimum boundary cell should be unique (single outlet)
        min_val = boundary.min()
        assert np.sum(boundary == min_val) == 1

    def test_interior_higher_than_outlet(self):
        """All interior cells should be higher than the outlet."""
        dem = generate_dem(size=64, seed=42)
        boundary = np.concatenate([
            dem[0, :], dem[-1, :], dem[:, 0], dem[:, -1]
        ])
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
        """D8 directions: 0-7 for 8 neighbors, -1 for outlet/boundary."""
        dem = generate_dem(size=32, seed=42)
        flow_dir, _ = compute_d8_flow(dem)
        valid_dirs = set(range(-1, 8))
        assert set(np.unique(flow_dir)).issubset(valid_dirs)

    def test_flow_accumulation_positive(self):
        dem = generate_dem(size=32, seed=42)
        _, flow_acc = compute_d8_flow(dem)
        assert flow_acc.min() >= 1  # Every cell drains at least itself

    def test_outlet_has_max_accumulation(self):
        """The outlet should have the highest flow accumulation."""
        dem = generate_dem(size=32, seed=42)
        _, flow_acc = compute_d8_flow(dem)
        # Outlet = lowest boundary cell
        boundary_coords = []
        n = dem.shape[0]
        for i in range(n):
            boundary_coords.extend([(0, i), (n-1, i), (i, 0), (i, n-1)])
        outlet = min(boundary_coords, key=lambda c: dem[c])
        assert flow_acc[outlet] == flow_acc.max()

    def test_simple_slope(self):
        """A pure left-right gradient should flow west."""
        # Each row is [0, 1, 2, 3] — values increase only left-to-right
        dem = np.tile(np.arange(4, dtype=np.float32), (4, 1))
        flow_dir, _ = compute_d8_flow(dem)
        # Direction 6 = west in D8 convention: N=0, NE=1, E=2, SE=3, S=4, SW=5, W=6, NW=7
        for r in range(1, 3):
            for c in range(1, 3):
                assert flow_dir[r, c] == 6, f"Cell ({r},{c}) should flow west"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_spatial_routing_terrain.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'spatial_routing_discovery'`

- [ ] **Step 3: Write `__init__.py`**

```python
# src/spatial_routing_discovery/__init__.py
"""Spatial Routing Discovery: Can CNNs learn water flow routing from DEM + rainfall?"""
```

- [ ] **Step 4: Write `terrain.py` implementation**

```python
# src/spatial_routing_discovery/terrain.py
"""Synthetic DEM generation and D8 flow direction computation."""

import numpy as np

# D8 neighbor offsets: N, NE, E, SE, S, SW, W, NW (shared with simulator)
_D8_DR = [-1, -1, 0, 1, 1, 1, 0, -1]
_D8_DC = [0, 1, 1, 1, 0, -1, -1, -1]


def generate_dem(size: int = 64, seed: int = 42) -> np.ndarray:
    """Generate a synthetic DEM with clear drainage structure.

    Creates terrain with a main valley and side ridges forming tributaries.
    The outlet (lowest boundary point) is at the bottom-center edge.

    Args:
        size: Grid dimension (size x size).
        seed: Random seed for reproducibility.

    Returns:
        DEM array of shape (size, size), dtype float32.
    """
    rng = np.random.RandomState(seed)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)

    # Normalize coordinates to [0, 1]
    xn = x / (size - 1)
    yn = y / (size - 1)

    # Base slope: terrain tilts toward bottom-center
    base = 2.0 * yn + 0.5 * (xn - 0.5) ** 2

    # Main valley running top-to-bottom, slightly off-center
    valley_x = 0.5 + 0.1 * np.sin(2 * np.pi * yn)
    main_valley = -1.5 * np.exp(-((xn - valley_x) ** 2) / 0.01)

    # Side ridges creating tributaries
    ridge1 = 0.8 * np.exp(-(((xn - 0.2) ** 2 + (yn - 0.3) ** 2) / 0.02))
    ridge2 = 0.8 * np.exp(-(((xn - 0.8) ** 2 + (yn - 0.5) ** 2) / 0.02))

    # Small-scale roughness
    noise = 0.05 * rng.randn(size, size).astype(np.float32)

    dem = base + main_valley + ridge1 + ridge2 + noise

    # Ensure single outlet at bottom-center
    outlet_col = size // 2
    dem[-1, outlet_col] = dem.min() - 0.1

    # Raise all other boundary cells above interior minimum
    interior_min = dem[1:-1, 1:-1].min()
    for r in range(size):
        for c in range(size):
            if r == 0 or r == size - 1 or c == 0 or c == size - 1:
                if not (r == size - 1 and c == outlet_col):
                    dem[r, c] = max(dem[r, c], interior_min + 0.05)

    return dem.astype(np.float32)


# D8 neighbor offsets: N, NE, E, SE, S, SW, W, NW
_D8_DR = [-1, -1, 0, 1, 1, 1, 0, -1]
_D8_DC = [0, 1, 1, 1, 0, -1, -1, -1]


def compute_d8_flow(dem: np.ndarray):
    """Compute D8 flow direction and flow accumulation.

    Args:
        dem: 2D array of elevations.

    Returns:
        Tuple of (flow_direction, flow_accumulation), both same shape as dem.
        flow_direction: int array, 0-7 for D8 directions, -1 for boundary outlets.
        flow_accumulation: int array, count of upstream cells (including self).
    """
    nrows, ncols = dem.shape
    flow_dir = np.full((nrows, ncols), -1, dtype=np.int8)

    # Compute flow direction for each cell
    for r in range(nrows):
        for c in range(ncols):
            max_drop = 0.0
            best_dir = -1
            for d in range(8):
                nr, nc = r + _D8_DR[d], c + _D8_DC[d]
                if 0 <= nr < nrows and 0 <= nc < ncols:
                    drop = dem[r, c] - dem[nr, nc]
                    # Diagonal distance is sqrt(2)
                    dist = 1.414 if d % 2 == 1 else 1.0
                    slope = drop / dist
                    if slope > max_drop:
                        max_drop = slope
                        best_dir = d
            flow_dir[r, c] = best_dir

    # Compute flow accumulation via topological sort
    flow_acc = np.ones((nrows, ncols), dtype=np.int32)

    # Count incoming edges
    in_degree = np.zeros((nrows, ncols), dtype=np.int32)
    for r in range(nrows):
        for c in range(ncols):
            d = flow_dir[r, c]
            if d >= 0:
                nr, nc = r + _D8_DR[d], c + _D8_DC[d]
                in_degree[nr, nc] += 1

    # BFS from sources (cells with no inflow)
    from collections import deque
    queue = deque()
    for r in range(nrows):
        for c in range(ncols):
            if in_degree[r, c] == 0:
                queue.append((r, c))

    while queue:
        r, c = queue.popleft()
        d = flow_dir[r, c]
        if d >= 0:
            nr, nc = r + _D8_DR[d], c + _D8_DC[d]
            flow_acc[nr, nc] += flow_acc[r, c]
            in_degree[nr, nc] -= 1
            if in_degree[nr, nc] == 0:
                queue.append((nr, nc))

    return flow_dir, flow_acc
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_spatial_routing_terrain.py -v`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add src/spatial_routing_discovery/__init__.py src/spatial_routing_discovery/terrain.py test/test_spatial_routing_terrain.py
git commit -m "feat(spatial-routing): add synthetic DEM generation and D8 flow computation"
```

---

### Task 2: Water Flow Simulator (`simulator.py`)

**Files:**
- Create: `src/spatial_routing_discovery/simulator.py`
- Create: `test/test_spatial_routing_simulator.py`

**Context:** A cellular automaton that simulates surface water flow over a DEM. Each timestep: (1) add rainfall, (2) distribute water to the steepest downslope neighbor(s), proportional to slope. This produces sequences of water depth grids that serve as training labels.

Key parameters:
- `flow_fraction`: how much water moves per step (0-1, controls speed)
- The simulation should conserve mass (total water in = rainfall + initial; total water out = water leaving via outlet)

- [ ] **Step 1: Write the failing tests**

```python
# test/test_spatial_routing_simulator.py
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
        """After one step, water should move toward lower cells."""
        rainfall = np.zeros_like(sim.dem)
        # Place water on a high cell
        high_r, high_c = np.unravel_index(sim.dem[1:-1, 1:-1].argmax(), sim.dem[1:-1, 1:-1].shape)
        high_r += 1
        high_c += 1
        sim.water[high_r, high_c] = 1.0
        sim.step()
        # Original cell should have less water
        assert sim.water[high_r, high_c] < 1.0

    def test_mass_conservation(self, sim):
        """Total water = remaining + outlet_loss, within tolerance."""
        rainfall = np.ones_like(sim.dem) * 0.01
        sim.add_rainfall(rainfall)
        total_added = sim.water.sum()
        for _ in range(5):
            sim.step()
        remaining = sim.water.sum()
        # Mass balance: what we added = what remains + what left via outlet
        np.testing.assert_allclose(
            remaining + sim.outlet_loss, total_added, rtol=1e-5
        )

    def test_run_sequence(self, sim):
        """run_sequence returns a list of water depth snapshots."""
        rainfall = np.ones_like(sim.dem) * 0.01
        seq = sim.run_sequence(rainfall_per_step=rainfall, n_steps=10)
        assert len(seq) == 10
        assert seq[0].shape == sim.dem.shape
        assert seq[0].dtype == np.float32

    def test_water_accumulates_in_valley(self, sim):
        """After sustained rainfall, water should concentrate along drainage."""
        rainfall = np.ones_like(sim.dem) * 0.02
        seq = sim.run_sequence(rainfall_per_step=rainfall, n_steps=50)
        final_water = seq[-1]
        from spatial_routing_discovery.terrain import compute_d8_flow
        _, flow_acc = compute_d8_flow(sim.dem)
        # High flow-accumulation cells should have more water than ridges
        threshold = np.percentile(flow_acc, 90)
        channel_mask = flow_acc >= threshold
        ridge_mask = flow_acc <= np.percentile(flow_acc, 10)
        assert final_water[channel_mask].mean() > final_water[ridge_mask].mean()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_spatial_routing_simulator.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'spatial_routing_discovery.simulator'`

- [ ] **Step 3: Write `simulator.py` implementation**

```python
# src/spatial_routing_discovery/simulator.py
"""Cellular automaton water flow simulator (D8-based, vectorized)."""

from typing import List, Optional

import numpy as np

from spatial_routing_discovery.terrain import compute_d8_flow, _D8_DR, _D8_DC


class WaterSimulator:
    """Simulates surface water flow over a DEM using pre-computed D8 routing.

    Pre-computes the flow direction once, then each timestep:
      1. Add rainfall to water grid
      2. Move flow_fraction of each cell's water to its D8 target
      3. Track water leaving the domain via outlet (outlet_loss)
    """

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
        """Add rainfall to current water depth."""
        self.water += rainfall.astype(np.float32)

    def step(self):
        """Advance one timestep: route water downhill (vectorized)."""
        transfer = np.where(self._has_target, self.water * self.flow_fraction, 0.0).astype(np.float32)
        self.water -= transfer

        # Accumulate inflow using np.add.at (handles duplicate targets)
        inflow = np.zeros_like(self.water)
        np.add.at(inflow, (self._target_r[self._has_target], self._target_c[self._has_target]),
                  transfer[self._has_target])

        # Water flowing to boundary cells that themselves have no target → outlet loss
        no_target = ~self._has_target
        boundary_inflow = inflow[no_target].sum()
        self.outlet_loss += float(boundary_inflow)

        # Only add inflow to cells that have a target (interior); outlet cells drain
        self.water += inflow
        # Remove water from cells without downstream target (outlet/boundary sinks)
        self.water[no_target] = 0.0

    def run_sequence(
        self,
        rainfall_per_step: np.ndarray,
        n_steps: int,
        rainfall_steps: Optional[int] = None,
    ) -> List[np.ndarray]:
        """Run simulation for n_steps, returning water depth snapshots.

        Args:
            rainfall_per_step: Rainfall to add each step (same shape as DEM).
            n_steps: Total number of simulation steps.
            rainfall_steps: Number of initial steps with rainfall (default: all).

        Returns:
            List of n_steps water depth arrays (float32).
        """
        if rainfall_steps is None:
            rainfall_steps = n_steps

        snapshots = []
        for t in range(n_steps):
            if t < rainfall_steps:
                self.add_rainfall(rainfall_per_step)
            self.step()
            snapshots.append(self.water.copy())

        return snapshots
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_spatial_routing_simulator.py -v`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/spatial_routing_discovery/simulator.py test/test_spatial_routing_simulator.py
git commit -m "feat(spatial-routing): add D8-based water flow simulator"
```

---

### Task 3: Rainfall Generator + PyTorch Dataset (`dataset.py`)

**Files:**
- Create: `src/spatial_routing_discovery/dataset.py`
- Create: `test/test_spatial_routing_dataset.py`

**Context:** Generate diverse rainfall events (uniform, localized storm, moving storm) and wrap simulated sequences into a PyTorch Dataset. Each sample is `(input_tensor, target_tensor)` where:
- `input_tensor`: shape `(3, H, W)` — channels are [DEM, current_water_depth, current_rainfall]
- `target_tensor`: shape `(1, H, W)` — next-timestep water depth

The dataset pre-generates multiple rainfall scenarios and simulates them, then serves individual timestep pairs.

- [ ] **Step 1: Write the failing tests**

```python
# test/test_spatial_routing_dataset.py
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
        # Localized rain should have higher values near center than edges
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
        return RoutingDataset(
            dem_size=16,
            dem_seed=42,
            n_events=3,
            steps_per_event=10,
            flow_fraction=0.5,
        )

    def test_length(self, dataset):
        # 3 events * 10 steps = 30 samples
        assert len(dataset) == 30

    def test_sample_shapes(self, dataset):
        x, y = dataset[0]
        assert x.shape == (3, 16, 16)  # [DEM, water, rainfall]
        assert y.shape == (1, 16, 16)  # next water depth

    def test_sample_dtype(self, dataset):
        x, y = dataset[0]
        assert x.dtype == torch.float32
        assert y.dtype == torch.float32

    def test_dem_channel_constant(self, dataset):
        """DEM channel should be the same across all samples."""
        x0, _ = dataset[0]
        x1, _ = dataset[1]
        torch.testing.assert_close(x0[0], x1[0])  # channel 0 = DEM

    def test_different_events_differ(self, dataset):
        """Samples from different events should have different rainfall."""
        x_event0, _ = dataset[0]
        x_event1, _ = dataset[10]  # First sample of second event
        # Rainfall channels should differ between events
        assert not torch.equal(x_event0[2], x_event1[2])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_spatial_routing_dataset.py -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 3: Write `dataset.py` implementation**

```python
# src/spatial_routing_discovery/dataset.py
"""Rainfall generation and PyTorch Dataset for routing experiments."""

from typing import List, Tuple

import numpy as np
import torch
from torch.utils.data import Dataset

from spatial_routing_discovery.terrain import generate_dem
from spatial_routing_discovery.simulator import WaterSimulator


def generate_rainfall_event(
    size: int,
    event_type: str = "uniform",
    seed: int = 0,
    intensity: float = 0.02,
) -> np.ndarray:
    """Generate a single rainfall field.

    Args:
        size: Grid dimension.
        event_type: One of "uniform", "localized", "moving".
        seed: Random seed.
        intensity: Base rainfall intensity.

    Returns:
        Rainfall array of shape (size, size), dtype float32.
    """
    rng = np.random.RandomState(seed)

    if event_type == "uniform":
        rain = np.full((size, size), intensity, dtype=np.float32)

    elif event_type == "localized":
        y, x = np.mgrid[0:size, 0:size].astype(np.float32)
        # Random center
        cy = rng.uniform(size * 0.2, size * 0.8)
        cx = rng.uniform(size * 0.2, size * 0.8)
        radius = rng.uniform(size * 0.1, size * 0.3)
        dist_sq = (y - cy) ** 2 + (x - cx) ** 2
        rain = intensity * 3.0 * np.exp(-dist_sq / (2 * radius ** 2))
        rain = rain.astype(np.float32)

    elif event_type == "moving":
        y, x = np.mgrid[0:size, 0:size].astype(np.float32)
        # Storm band moving across the grid
        angle = rng.uniform(0, np.pi)
        offset = rng.uniform(size * 0.3, size * 0.7)
        proj = x * np.cos(angle) + y * np.sin(angle)
        rain = intensity * 2.0 * np.exp(-((proj - offset) ** 2) / (2 * (size * 0.1) ** 2))
        rain = rain.astype(np.float32)

    else:
        raise ValueError(f"Unknown event_type: {event_type}")

    return rain


class RoutingDataset(Dataset):
    """Dataset of (input, target) pairs from simulated water flow.

    Each sample:
        input:  (3, H, W) tensor — [DEM, current_water, current_rainfall]
        target: (1, H, W) tensor — next-timestep water depth
    """

    def __init__(
        self,
        dem_size: int = 64,
        dem_seed: int = 42,
        n_events: int = 50,
        steps_per_event: int = 20,
        flow_fraction: float = 0.5,
    ):
        self.dem = generate_dem(size=dem_size, seed=dem_seed)
        # Normalize DEM to [0, 1] for network input
        self.dem_norm = (self.dem - self.dem.min()) / (self.dem.max() - self.dem.min() + 1e-8)

        event_types = ["uniform", "localized", "moving"]
        self.samples: List[Tuple[np.ndarray, np.ndarray, np.ndarray]] = []

        for event_idx in range(n_events):
            etype = event_types[event_idx % len(event_types)]
            rainfall = generate_rainfall_event(
                size=dem_size, event_type=etype, seed=event_idx * 7 + 1
            )

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

        x = np.stack([self.dem_norm, water_before, rainfall], axis=0)  # (3, H, W)
        y = water_after[np.newaxis, ...]  # (1, H, W)

        return torch.from_numpy(x).float(), torch.from_numpy(y).float()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_spatial_routing_dataset.py -v`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/spatial_routing_discovery/dataset.py test/test_spatial_routing_dataset.py
git commit -m "feat(spatial-routing): add rainfall generator and PyTorch dataset"
```

---

### Task 4: CNN Models at Different Depths (`models.py`)

**Files:**
- Create: `src/spatial_routing_discovery/models.py`
- Create: `test/test_spatial_routing_models.py`

**Context:** Three CNN architectures with different depths (2, 4, 8 conv layers), all producing the same output shape. We need:
- `RoutingCNN(depth=N)`: parameterized by depth
- A `get_feature_maps(model, x)` function that returns intermediate feature maps from each layer — this is critical for the analysis phase

All models use same kernel size (3x3), same channel width, padding to preserve spatial size.

- [ ] **Step 1: Write the failing tests**

```python
# test/test_spatial_routing_models.py
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
        """Water depth should be non-negative (ReLU on output)."""
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
        """Should work on small grids too."""
        model = RoutingCNN(depth=4, in_channels=3, hidden_channels=16)
        x = torch.randn(1, 3, 16, 16)
        y = model(x)
        assert y.shape == (1, 1, 16, 16)


class TestGetFeatureMaps:
    def test_returns_all_layers(self):
        model = RoutingCNN(depth=4, hidden_channels=32)
        x = torch.randn(1, 3, 64, 64)
        fmaps = get_feature_maps(model, x)
        assert len(fmaps) == 4  # One per conv layer

    def test_feature_map_shapes(self):
        model = RoutingCNN(depth=4, hidden_channels=32)
        x = torch.randn(1, 3, 64, 64)
        fmaps = get_feature_maps(model, x)
        for fm in fmaps:
            assert fm.shape[0] == 1  # batch
            assert fm.shape[2] == 64  # spatial preserved
            assert fm.shape[3] == 64

    def test_feature_maps_differ_with_input(self):
        """Different inputs should produce different feature maps."""
        model = RoutingCNN(depth=4, hidden_channels=32)
        x1 = torch.randn(1, 3, 64, 64)
        x2 = torch.randn(1, 3, 64, 64)
        fm1 = get_feature_maps(model, x1)
        fm2 = get_feature_maps(model, x2)
        assert not torch.equal(fm1[0], fm2[0])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_spatial_routing_models.py -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 3: Write `models.py` implementation**

```python
# src/spatial_routing_discovery/models.py
"""CNN architectures at different depths for spatial routing prediction."""

from typing import List

import torch
import torch.nn as nn


class RoutingCNN(nn.Module):
    """Simple CNN with configurable depth for water depth prediction.

    All conv layers use 3x3 kernels with padding=1 to preserve spatial size.
    Final output is passed through ReLU to ensure non-negative water depth.

    Args:
        depth: Number of convolutional layers (2, 4, or 8).
        in_channels: Input channels (default 3: DEM + water + rainfall).
        hidden_channels: Number of channels in hidden layers.
    """

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
    """Extract intermediate feature maps from each conv layer.

    Args:
        model: A RoutingCNN instance.
        x: Input tensor of shape (B, C, H, W).

    Returns:
        List of tensors, one per convolutional layer, each (B, hidden_channels, H, W).
    """
    feature_maps = []
    h = x
    for layer in model.features:
        h = layer(h)
        if isinstance(layer, nn.ReLU):
            feature_maps.append(h.detach().clone())
    return feature_maps
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_spatial_routing_models.py -v`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/spatial_routing_discovery/models.py test/test_spatial_routing_models.py
git commit -m "feat(spatial-routing): add depth-configurable CNN with feature map extraction"
```

---

### Task 5: Analysis Suite (`analysis.py`)

**Files:**
- Create: `src/spatial_routing_discovery/analysis.py`
- Create: `test/test_spatial_routing_analysis.py`

**Context:** Functions to analyze whether CNN feature maps show routing-like behavior:
1. `correlation_with_drainage(feature_map, flow_acc)` — do high activations align with high flow accumulation?
2. `dynamic_response_score(model, dem_tensor, rainfall_a, rainfall_b)` — same DEM, different rainfall: how much do feature maps change?
3. `depth_routing_score(model, dataset)` — per-layer correlation with drainage, to see if deeper = more drainage-aligned

- [ ] **Step 1: Write the failing tests**

```python
# test/test_spatial_routing_analysis.py
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
        """If feature map equals flow_acc, correlation should be ~1."""
        flow_acc = np.random.rand(32, 32).astype(np.float32)
        feature_map = flow_acc.copy()
        corr = correlation_with_drainage(feature_map, flow_acc)
        assert abs(corr - 1.0) < 1e-5

    def test_random_low_correlation(self):
        """Random feature map should have low correlation with drainage."""
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
        """Same rainfall twice should give near-zero dynamic response."""
        model = RoutingCNN(depth=2, hidden_channels=16)
        model.eval()
        dem = torch.randn(1, 1, 16, 16)
        rain = torch.randn(1, 1, 16, 16)
        score = dynamic_response_score(model, dem, rain, rain)
        assert score < 1e-5

    def test_different_input_positive_score(self):
        """Different rainfall should give positive dynamic response."""
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
        x[0, 1] = torch.randn(16, 16) * 0.01  # water
        x[0, 2] = torch.randn(16, 16).abs() * 0.02  # rainfall

        scores = depth_routing_scores(model, x, flow_acc)
        assert len(scores) == 4
        assert all(isinstance(s, float) for s in scores)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_spatial_routing_analysis.py -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 3: Write `analysis.py` implementation**

```python
# src/spatial_routing_discovery/analysis.py
"""Analysis tools for evaluating whether CNN learns spatial routing."""

from typing import List

import numpy as np
import torch

from spatial_routing_discovery.models import RoutingCNN, get_feature_maps


def correlation_with_drainage(feature_map: np.ndarray, flow_acc: np.ndarray) -> float:
    """Pearson correlation between a 2D feature map and flow accumulation.

    Args:
        feature_map: 2D array, e.g. mean activation across channels.
        flow_acc: 2D array of D8 flow accumulation values.

    Returns:
        Pearson correlation coefficient (float).
    """
    fm_flat = feature_map.flatten().astype(np.float64)
    fa_flat = flow_acc.flatten().astype(np.float64)

    fm_centered = fm_flat - fm_flat.mean()
    fa_centered = fa_flat - fa_flat.mean()

    numer = (fm_centered * fa_centered).sum()
    denom = np.sqrt((fm_centered ** 2).sum() * (fa_centered ** 2).sum())

    if denom < 1e-12:
        return 0.0
    return float(numer / denom)


def dynamic_response_score(
    model: RoutingCNN,
    dem: torch.Tensor,
    rainfall_a: torch.Tensor,
    rainfall_b: torch.Tensor,
) -> float:
    """Measure how much feature maps change when rainfall changes but DEM stays fixed.

    Constructs two inputs sharing the same DEM (channel 0) and zero water (channel 1),
    but different rainfall (channel 2). Returns mean L2 distance across all layers.

    Args:
        model: Trained RoutingCNN.
        dem: DEM tensor of shape (1, 1, H, W).
        rainfall_a: First rainfall tensor of shape (1, 1, H, W).
        rainfall_b: Second rainfall tensor of shape (1, 1, H, W).

    Returns:
        Mean L2 distance between feature maps (float).
    """
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


def depth_routing_scores(
    model: RoutingCNN,
    x: torch.Tensor,
    flow_acc: np.ndarray,
) -> List[float]:
    """Per-layer correlation between mean feature activation and flow accumulation.

    Args:
        model: RoutingCNN instance.
        x: Input tensor (1, 3, H, W).
        flow_acc: 2D flow accumulation array.

    Returns:
        List of correlation values, one per convolutional layer.
    """
    with torch.no_grad():
        fmaps = get_feature_maps(model, x)

    scores = []
    for fm in fmaps:
        # Mean activation across channels → (H, W)
        mean_activation = fm[0].mean(dim=0).cpu().numpy()
        corr = correlation_with_drainage(mean_activation, flow_acc)
        scores.append(corr)

    return scores
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_spatial_routing_analysis.py -v`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/spatial_routing_discovery/analysis.py test/test_spatial_routing_analysis.py
git commit -m "feat(spatial-routing): add drainage correlation and dynamic response analysis"
```

---

### Task 6: Experiment Runner (`scripts/run_experiment.py`)

**Files:**
- Create: `src/spatial_routing_discovery/scripts/__init__.py`
- Create: `src/spatial_routing_discovery/scripts/run_experiment.py`

**Context:** End-to-end script: generate data → train models at depth 2/4/8 → evaluate prediction accuracy → run analysis → save results. No test file for this task — it's a script that orchestrates already-tested components. Output goes to `results/spatial_routing_discovery/`.

- [ ] **Step 1: Create scripts `__init__.py`**

```python
# src/spatial_routing_discovery/scripts/__init__.py
"""Runnable scripts for spatial routing discovery experiments."""
```

- [ ] **Step 2: Write `run_experiment.py`**

```python
# src/spatial_routing_discovery/scripts/run_experiment.py
"""End-to-end experiment: generate data, train CNNs at different depths, analyze.

Usage:
    cd <project_root>/src
    python -m spatial_routing_discovery.scripts.run_experiment [--dem-size 64] [--epochs 50]
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, random_split

# Ensure src/ is on path
_SRC_DIR = Path(__file__).resolve().parents[2]
if str(_SRC_DIR) not in sys.path:
    sys.path.insert(0, str(_SRC_DIR))

from spatial_routing_discovery.dataset import RoutingDataset
from spatial_routing_discovery.models import RoutingCNN
from spatial_routing_discovery.terrain import generate_dem, compute_d8_flow
from spatial_routing_discovery.analysis import (
    dynamic_response_score,
    depth_routing_scores,
)


def train_model(model, train_loader, val_loader, epochs, device, lr=1e-3):
    """Train and return best validation loss."""
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    criterion = nn.MSELoss()
    best_val_loss = float("inf")

    for epoch in range(epochs):
        # Train
        model.train()
        train_loss = 0.0
        for x, y in train_loader:
            x, y = x.to(device), y.to(device)
            pred = model(x)
            loss = criterion(pred, y)
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            train_loss += loss.item() * x.size(0)
        train_loss /= len(train_loader.dataset)

        # Validate
        model.eval()
        val_loss = 0.0
        with torch.no_grad():
            for x, y in val_loader:
                x, y = x.to(device), y.to(device)
                pred = model(x)
                val_loss += criterion(pred, y).item() * x.size(0)
        val_loss /= len(val_loader.dataset)

        if val_loss < best_val_loss:
            best_val_loss = val_loss

        if (epoch + 1) % 10 == 0:
            print(f"  Epoch {epoch+1}/{epochs}  train_loss={train_loss:.6f}  val_loss={val_loss:.6f}")

    return best_val_loss


def analyze_model(model, dataset, dem, flow_acc, device):
    """Run analysis on a trained model."""
    model.eval()

    # 1. Depth routing scores (per-layer correlation with drainage)
    x_sample, _ = dataset[0]
    x_sample = x_sample.unsqueeze(0).to(device)
    layer_scores = depth_routing_scores(model, x_sample, flow_acc)

    # 2. Dynamic response: same DEM, different rainfall
    dem_norm = (dem - dem.min()) / (dem.max() - dem.min() + 1e-8)
    dem_t = torch.from_numpy(dem_norm).float().unsqueeze(0).unsqueeze(0).to(device)
    rain_a = torch.ones(1, 1, dem.shape[0], dem.shape[1]).to(device) * 0.02
    rain_b = torch.zeros(1, 1, dem.shape[0], dem.shape[1]).to(device)
    rain_b[0, 0, dem.shape[0] // 4, dem.shape[1] // 4] = 0.5  # localized storm
    dyn_score = dynamic_response_score(model, dem_t, rain_a, rain_b)

    return {
        "layer_drainage_correlations": layer_scores,
        "dynamic_response_score": dyn_score,
    }


def main():
    parser = argparse.ArgumentParser(description="Spatial routing discovery experiment")
    parser.add_argument("--dem-size", type=int, default=64)
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--n-events", type=int, default=60)
    parser.add_argument("--steps-per-event", type=int, default=20)
    parser.add_argument("--hidden-channels", type=int, default=32)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--output-dir", type=str, default=None)
    args = parser.parse_args()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    # Output directory
    if args.output_dir:
        out_dir = Path(args.output_dir)
    else:
        out_dir = Path(__file__).resolve().parents[3] / "results" / "spatial_routing_discovery"
    out_dir.mkdir(parents=True, exist_ok=True)

    # Generate DEM and ground truth
    print("Generating DEM and computing D8 flow...")
    dem = generate_dem(size=args.dem_size, seed=42)
    _, flow_acc = compute_d8_flow(dem)
    np.save(out_dir / "dem.npy", dem)
    np.save(out_dir / "flow_acc.npy", flow_acc)

    # Generate dataset
    print(f"Generating dataset: {args.n_events} events x {args.steps_per_event} steps...")
    dataset = RoutingDataset(
        dem_size=args.dem_size,
        dem_seed=42,
        n_events=args.n_events,
        steps_per_event=args.steps_per_event,
    )

    # Split 80/20
    n_val = len(dataset) // 5
    n_train = len(dataset) - n_val
    train_set, val_set = random_split(dataset, [n_train, n_val],
                                      generator=torch.Generator().manual_seed(42))
    train_loader = DataLoader(train_set, batch_size=args.batch_size, shuffle=True)
    val_loader = DataLoader(val_set, batch_size=args.batch_size)

    results = {}
    for depth in [2, 4, 8]:
        print(f"\n{'='*60}")
        print(f"Training CNN depth={depth}")
        print(f"{'='*60}")

        model = RoutingCNN(
            depth=depth,
            in_channels=3,
            hidden_channels=args.hidden_channels,
        ).to(device)

        n_params = sum(p.numel() for p in model.parameters())
        print(f"  Parameters: {n_params:,}")

        best_val = train_model(model, train_loader, val_loader, args.epochs, device)
        print(f"  Best val loss: {best_val:.6f}")

        # Save model
        torch.save(model.state_dict(), out_dir / f"model_depth{depth}.pt")

        # Analyze
        analysis = analyze_model(model, dataset, dem, flow_acc, device)
        analysis["best_val_loss"] = best_val
        analysis["n_params"] = n_params
        results[f"depth_{depth}"] = analysis

        print(f"  Layer drainage correlations: {analysis['layer_drainage_correlations']}")
        print(f"  Dynamic response score: {analysis['dynamic_response_score']:.4f}")

    # Save results
    # Convert numpy types for JSON serialization
    def to_serializable(obj):
        if isinstance(obj, (np.floating, np.integer)):
            return float(obj)
        if isinstance(obj, np.ndarray):
            return obj.tolist()
        if isinstance(obj, list):
            return [to_serializable(i) for i in obj]
        if isinstance(obj, dict):
            return {k: to_serializable(v) for k, v in obj.items()}
        return obj

    with open(out_dir / "results.json", "w") as f:
        json.dump(to_serializable(results), f, indent=2)

    print(f"\nResults saved to {out_dir}")
    print("\nSummary:")
    print(f"{'Depth':<8} {'Val Loss':<12} {'Dynamic':<12} {'Layer Correlations'}")
    print("-" * 70)
    for depth in [2, 4, 8]:
        r = results[f"depth_{depth}"]
        corrs = ", ".join(f"{c:.3f}" for c in r["layer_drainage_correlations"])
        print(f"{depth:<8} {r['best_val_loss']:<12.6f} {r['dynamic_response_score']:<12.4f} [{corrs}]")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Smoke test the script**

Run: `cd G:/github/pycharm/projects/neuralhydrology/src && python -m spatial_routing_discovery.scripts.run_experiment --dem-size 16 --epochs 5 --n-events 6 --steps-per-event 5`
Expected: Script runs to completion, prints summary table, saves results to `results/spatial_routing_discovery/`

- [ ] **Step 4: Commit**

```bash
git add src/spatial_routing_discovery/scripts/__init__.py src/spatial_routing_discovery/scripts/run_experiment.py
git commit -m "feat(spatial-routing): add end-to-end experiment runner script"
```

---

### Task 7: Feature Map Visualization (`scripts/visualize_features.py`)

**Files:**
- Create: `src/spatial_routing_discovery/scripts/visualize_features.py`

**Context:** Standalone visualization script that loads a trained model and produces the key figures:
1. DEM + ground truth flow accumulation (reference)
2. Per-layer feature maps for two different rainfall inputs (dynamic response)
3. Overlay of high-activation regions on drainage network (routing emergence)

This is the "money plot" — the figure that answers whether the CNN learned routing.

- [ ] **Step 1: Write `visualize_features.py`**

```python
# src/spatial_routing_discovery/scripts/visualize_features.py
"""Visualize CNN feature maps and compare with drainage network.

Usage:
    cd <project_root>/src
    python -m spatial_routing_discovery.scripts.visualize_features \
        --results-dir ../results/spatial_routing_discovery \
        --depth 4
"""

import argparse
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import torch

_SRC_DIR = Path(__file__).resolve().parents[2]
if str(_SRC_DIR) not in sys.path:
    sys.path.insert(0, str(_SRC_DIR))

from spatial_routing_discovery.models import RoutingCNN, get_feature_maps
from spatial_routing_discovery.terrain import compute_d8_flow
from spatial_routing_discovery.dataset import generate_rainfall_event


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", type=str, required=True)
    parser.add_argument("--depth", type=int, default=4)
    parser.add_argument("--hidden-channels", type=int, default=32)
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    dem = np.load(results_dir / "dem.npy")
    flow_acc = np.load(results_dir / "flow_acc.npy")
    size = dem.shape[0]

    # Load model
    model = RoutingCNN(depth=args.depth, in_channels=3, hidden_channels=args.hidden_channels)
    model.load_state_dict(torch.load(results_dir / f"model_depth{args.depth}.pt", map_location="cpu", weights_only=True))
    model.eval()

    dem_norm = (dem - dem.min()) / (dem.max() - dem.min() + 1e-8)

    # Two rainfall scenarios
    rain_uniform = generate_rainfall_event(size=size, event_type="uniform", seed=0)
    rain_local = generate_rainfall_event(size=size, event_type="localized", seed=42)

    def make_input(rainfall):
        x = np.stack([dem_norm, np.zeros_like(dem), rainfall], axis=0)
        return torch.from_numpy(x).float().unsqueeze(0)

    x_uniform = make_input(rain_uniform)
    x_local = make_input(rain_local)

    with torch.no_grad():
        fm_uniform = get_feature_maps(model, x_uniform)
        fm_local = get_feature_maps(model, x_local)

    # Compute log flow accumulation for visualization
    log_flow_acc = np.log1p(flow_acc.astype(np.float32))

    n_layers = len(fm_uniform)

    # Figure 1: Reference — DEM + drainage
    fig, axes = plt.subplots(1, 3, figsize=(15, 4))
    axes[0].imshow(dem, cmap="terrain")
    axes[0].set_title("DEM")
    axes[1].imshow(log_flow_acc, cmap="Blues")
    axes[1].set_title("Flow Accumulation (log)")
    axes[2].imshow(rain_local, cmap="YlGnBu")
    axes[2].set_title("Localized Rainfall")
    for ax in axes:
        ax.axis("off")
    plt.tight_layout()
    plt.savefig(results_dir / f"fig1_reference_depth{args.depth}.png", dpi=150)
    plt.close()

    # Figure 2: Per-layer feature maps for two rainfall scenarios
    fig, axes = plt.subplots(3, n_layers, figsize=(4 * n_layers, 12))
    for i in range(n_layers):
        # Mean activation across channels
        act_uniform = fm_uniform[i][0].mean(dim=0).cpu().numpy()
        act_local = fm_local[i][0].mean(dim=0).cpu().numpy()
        act_diff = np.abs(act_uniform - act_local)

        axes[0, i].imshow(act_uniform, cmap="hot")
        axes[0, i].set_title(f"Layer {i+1}\nUniform Rain")
        axes[0, i].axis("off")

        axes[1, i].imshow(act_local, cmap="hot")
        axes[1, i].set_title(f"Layer {i+1}\nLocalized Rain")
        axes[1, i].axis("off")

        axes[2, i].imshow(act_diff, cmap="magma")
        axes[2, i].set_title(f"Layer {i+1}\n|Difference|")
        axes[2, i].axis("off")

    plt.suptitle(f"Feature Maps: Uniform vs Localized Rainfall (depth={args.depth})", fontsize=14)
    plt.tight_layout()
    plt.savefig(results_dir / f"fig2_dynamic_response_depth{args.depth}.png", dpi=150)
    plt.close()

    # Figure 3: Overlay — highest activation vs drainage
    fig, axes = plt.subplots(1, n_layers, figsize=(4 * n_layers, 4))
    if n_layers == 1:
        axes = [axes]
    channel_mask = log_flow_acc > np.percentile(log_flow_acc, 80)

    for i in range(n_layers):
        act = fm_local[i][0].mean(dim=0).cpu().numpy()
        act_thresh = act > np.percentile(act, 80)

        # Red = drainage, Blue = high activation, Purple = overlap
        overlay = np.zeros((*dem.shape, 3))
        overlay[channel_mask, 0] = 1.0  # Red channel for drainage
        overlay[act_thresh, 2] = 1.0  # Blue channel for activation
        # Overlap → purple

        axes[i].imshow(overlay)
        axes[i].set_title(f"Layer {i+1}")
        axes[i].axis("off")

    plt.suptitle(f"Red=Drainage  Blue=High Activation  Purple=Overlap (depth={args.depth})", fontsize=12)
    plt.tight_layout()
    plt.savefig(results_dir / f"fig3_overlay_depth{args.depth}.png", dpi=150)
    plt.close()

    print(f"Figures saved to {results_dir}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run visualization (after Task 6 has been run)**

Run: `cd G:/github/pycharm/projects/neuralhydrology/src && python -m spatial_routing_discovery.scripts.visualize_features --results-dir ../results/spatial_routing_discovery --depth 4`
Expected: Three PNG figures saved to results directory

- [ ] **Step 3: Commit**

```bash
git add src/spatial_routing_discovery/scripts/visualize_features.py
git commit -m "feat(spatial-routing): add feature map visualization script"
```

---

### Task 8: Full Experiment Run + Results Interpretation

**Files:** No new files. This task runs the full experiment and interprets results.

- [ ] **Step 1: Run all tests**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_spatial_routing_*.py -v`
Expected: All tests PASS

- [ ] **Step 2: Run full experiment**

Run: `cd G:/github/pycharm/projects/neuralhydrology/src && python -m spatial_routing_discovery.scripts.run_experiment --dem-size 64 --epochs 50 --n-events 60 --steps-per-event 20`
Expected: ~15-30 minutes on CPU. Results saved to `results/spatial_routing_discovery/`

- [ ] **Step 3: Generate visualization for each depth**

```bash
cd G:/github/pycharm/projects/neuralhydrology/src
python -m spatial_routing_discovery.scripts.visualize_features --results-dir ../results/spatial_routing_discovery --depth 2
python -m spatial_routing_discovery.scripts.visualize_features --results-dir ../results/spatial_routing_discovery --depth 4
python -m spatial_routing_discovery.scripts.visualize_features --results-dir ../results/spatial_routing_discovery --depth 8
```

- [ ] **Step 4: Interpret results**

Check `results/spatial_routing_discovery/results.json` and the figures. Key questions:

1. **Prediction accuracy**: Does deeper CNN predict water depth better? (Compare val_loss across depths)
2. **Dynamic response**: Is `dynamic_response_score > 0` for trained models? If yes → features are NOT static terrain recognition
3. **Routing emergence**: Do `layer_drainage_correlations` increase with layer depth? If yes → deeper layers capture larger-scale drainage structure
4. **Overlay figures**: Is there purple (overlap) in fig3? If yes → CNN activations align with drainage without being told

**Known limitations to discuss:**
- **Receptive field**: depth-8 CNN with 3x3 kernels has receptive field 17x17, only ~1/4 of the 64x64 grid. True long-range routing may require dilated convolutions or attention in future work.
- **Single-step prediction**: The model only predicts one step ahead, where water moves at most 1 cell. A shallow CNN could succeed by learning local slope-following without global routing understanding. If shallow models perform equally well on prediction accuracy, the drainage correlation analysis becomes the critical discriminator.
- **Synthetic labels**: Training labels come from our D8 simulator, not real observations. This experiment answers "can a CNN learn D8 routing as an emergent computation" — not "can it learn real hydrology." Real-data validation is a separate follow-up.

- [ ] **Step 5: Commit results summary**

```bash
git add results/spatial_routing_discovery/results.json
git commit -m "results(spatial-routing): add experiment results for depth 2/4/8"
```
