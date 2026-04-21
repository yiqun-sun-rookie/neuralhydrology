"""Synthetic DEM generation and D8 flow direction computation."""

import heapq

import numpy as np

# D8 neighbor offsets: N, NE, E, SE, S, SW, W, NW (shared with simulator)
_D8_DR = [-1, -1, 0, 1, 1, 1, 0, -1]
_D8_DC = [0, 1, 1, 1, 0, -1, -1, -1]


def _fill_pits(dem: np.ndarray) -> np.ndarray:
    """Priority-flood pit filling with epsilon gradient (Barnes et al., 2014).

    Fills depressions so every cell can drain to the boundary.  Filled cells
    are raised to *slightly above* the level of the cell that drained them,
    guaranteeing a positive slope through former flat areas.
    """
    eps = np.float32(1e-5)
    nrows, ncols = dem.shape
    filled = dem.astype(np.float64).copy()  # use float64 for epsilon precision
    visited = np.zeros((nrows, ncols), dtype=bool)
    heap = []  # (elevation, row, col)
    # Seed boundary cells
    for r in range(nrows):
        for c in range(ncols):
            if r == 0 or r == nrows - 1 or c == 0 or c == ncols - 1:
                heapq.heappush(heap, (filled[r, c], r, c))
                visited[r, c] = True
    # Process cells in elevation order
    while heap:
        elev, r, c = heapq.heappop(heap)
        for d in range(8):
            nr, nc = r + _D8_DR[d], c + _D8_DC[d]
            if 0 <= nr < nrows and 0 <= nc < ncols and not visited[nr, nc]:
                visited[nr, nc] = True
                if filled[nr, nc] <= elev:
                    # Raise to parent elevation + epsilon to ensure positive slope
                    filled[nr, nc] = elev + eps
                heapq.heappush(heap, (filled[nr, nc], nr, nc))
    return filled.astype(np.float32)


def generate_dem(size: int = 64, seed: int = 42) -> np.ndarray:
    rng = np.random.RandomState(seed)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    xn = x / (size - 1)
    yn = y / (size - 1)
    base = 2.0 * yn + 0.5 * (xn - 0.5) ** 2
    valley_x = 0.5 + 0.1 * np.sin(2 * np.pi * yn)
    main_valley = -1.5 * np.exp(-((xn - valley_x) ** 2) / 0.01)
    ridge1 = 0.8 * np.exp(-(((xn - 0.2) ** 2 + (yn - 0.3) ** 2) / 0.02))
    ridge2 = 0.8 * np.exp(-(((xn - 0.8) ** 2 + (yn - 0.5) ** 2) / 0.02))
    noise = 0.05 * rng.randn(size, size).astype(np.float32)
    dem = base + main_valley + ridge1 + ridge2 + noise
    outlet_col = size // 2
    # Raise all boundary cells above the interior maximum so the only exit is the outlet
    interior_max = dem[1:-1, 1:-1].max()
    boundary_elev = interior_max + 0.5
    for r in range(size):
        for c in range(size):
            if r == 0 or r == size - 1 or c == 0 or c == size - 1:
                dem[r, c] = boundary_elev
    # Set the outlet as the global minimum
    dem[-1, outlet_col] = dem[1:-1, 1:-1].min() - 0.1
    dem = _fill_pits(dem)
    return dem.astype(np.float32)


def compute_d8_flow(dem: np.ndarray):
    nrows, ncols = dem.shape
    flow_dir = np.full((nrows, ncols), -1, dtype=np.int8)
    for r in range(nrows):
        for c in range(ncols):
            max_drop = 0.0
            best_dir = -1
            for d in range(8):
                nr, nc = r + _D8_DR[d], c + _D8_DC[d]
                if 0 <= nr < nrows and 0 <= nc < ncols:
                    drop = dem[r, c] - dem[nr, nc]
                    dist = 1.414 if d % 2 == 1 else 1.0
                    slope = drop / dist
                    if slope > max_drop:
                        max_drop = slope
                        best_dir = d
            flow_dir[r, c] = best_dir
    flow_acc = np.ones((nrows, ncols), dtype=np.int32)
    in_degree = np.zeros((nrows, ncols), dtype=np.int32)
    for r in range(nrows):
        for c in range(ncols):
            d = flow_dir[r, c]
            if d >= 0:
                nr, nc = r + _D8_DR[d], c + _D8_DC[d]
                in_degree[nr, nc] += 1
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
