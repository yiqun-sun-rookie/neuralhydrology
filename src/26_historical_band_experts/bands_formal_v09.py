"""Memory-bounded causal window and continuous-history extraction for version 09."""
from __future__ import annotations

import numpy as np
import torch

from formal_v09_protocol import history_edges_v09
from memory_safety_v09 import HostMemorySnapshot, MemorySafetyGate, sample_host_memory


_WINDOW_DAYS = 3_562
_RECENT_DAYS = 270
_FEATURES = 5
_HISTORY_BINS = 120
_MIN_WIDTH = 6.0
_MAX_WIDTH = 76.0


def _as_index_array(values, label: str) -> np.ndarray:
    array = np.asarray(values)
    if array.ndim != 1 or array.size == 0:
        raise ValueError(f"{label} must be a nonempty one-dimensional array")
    if not np.issubdtype(array.dtype, np.integer):
        raise TypeError(f"{label} must contain integers")
    return array.astype(np.int64, copy=False)


def gather_causal_windows_v09(
    forcing: np.ndarray,
    basin_indices,
    target_indices,
    *,
    gate: MemorySafetyGate | None = None,
    snapshot: HostMemorySnapshot | None = None,
) -> np.ndarray:
    """Copy at most one batch of 3,562-day windows from an array or memory map."""
    if forcing.ndim != 3 or forcing.shape[-1] != _FEATURES:
        raise ValueError("forcing must have shape [basin,time,5]")
    if forcing.dtype != np.float32:
        raise ValueError("forcing must use float32 storage")
    basin_indices = _as_index_array(basin_indices, "basin_indices")
    target_indices = _as_index_array(target_indices, "target_indices")
    if basin_indices.shape != target_indices.shape:
        raise ValueError("basin_indices and target_indices must have identical shape")
    if basin_indices.size > 256:
        raise ValueError("one version 09 window batch cannot exceed 256 samples")
    if int(basin_indices.min()) < 0 or int(basin_indices.max()) >= forcing.shape[0]:
        raise IndexError("basin index is outside forcing")
    if int(target_indices.min()) < _WINDOW_DAYS - 1:
        raise ValueError("every target index must be at least 3561")
    if int(target_indices.max()) >= forcing.shape[1]:
        raise IndexError("target index is outside forcing")

    if snapshot is None:
        snapshot = sample_host_memory()
    if gate is None:
        gate = MemorySafetyGate.from_snapshot(snapshot)
    gate.assert_allocation_safe(
        snapshot,
        (basin_indices.size, _WINDOW_DAYS, _FEATURES),
        np.float32,
        copies=4,
    )

    windows = np.empty((basin_indices.size, _WINDOW_DAYS, _FEATURES), dtype=np.float32)
    for row, (basin_index, target_index) in enumerate(zip(basin_indices, target_indices)):
        start = int(target_index) - _WINDOW_DAYS + 1
        source = forcing[int(basin_index), start:int(target_index) + 1]
        if source.shape != (_WINDOW_DAYS, _FEATURES):
            raise RuntimeError("forcing window shape changed during the bounded copy")
        np.copyto(windows[row], source, casting="no")
    return windows


def _duration_coordinate(width: int) -> float:
    return float((np.log(float(width)) - np.log(_MIN_WIDTH)) / (np.log(_MAX_WIDTH) - np.log(_MIN_WIDTH)))


def _age_coordinate(low_lag: int, high_lag_exclusive: int) -> float:
    midpoint = 0.5 * (low_lag + high_lag_exclusive - 1)
    return float((np.log(midpoint) - np.log(270.0)) / (np.log(3561.0) - np.log(270.0)))


def _deterministic_cumsum_dim1_v09(values: torch.Tensor) -> torch.Tensor:
    """Compute the dimension-one prefix sum with deterministic CUDA operations."""
    running = torch.zeros_like(values[:, 0])
    cumulative = []
    for item in values.unbind(dim=1):
        running = running + item
        cumulative.append(running)
    return torch.stack(cumulative, dim=1)


def split_windows_v09(windows: torch.Tensor) -> dict[str, torch.Tensor]:
    """Split a bounded chronological window batch into recent days and history bins."""
    if windows.ndim != 3 or tuple(windows.shape[1:]) != (_WINDOW_DAYS, _FEATURES):
        raise ValueError("windows must have shape [batch,3562,5]")
    if windows.shape[0] == 0 or windows.shape[0] > 256:
        raise ValueError("one version 09 window batch must contain from 1 through 256 samples")
    if not windows.is_floating_point():
        raise TypeError("windows must be floating point")
    recent = windows[:, -_RECENT_DAYS:]
    prefix = torch.cat(
        (
            torch.zeros(
                windows.shape[0],
                1,
                windows.shape[2],
                dtype=windows.dtype,
                device=windows.device,
            ),
            _deterministic_cumsum_dim1_v09(windows),
        ),
        dim=1,
    )
    edges = history_edges_v09()
    pooled = []
    for edge_index in reversed(range(_HISTORY_BINS)):
        low_lag = int(edges[edge_index])
        high_lag_exclusive = int(edges[edge_index + 1])
        start = _WINDOW_DAYS - high_lag_exclusive
        end = _WINDOW_DAYS - low_lag
        width = high_lag_exclusive - low_lag
        forcing_mean = (prefix[:, end] - prefix[:, start]) / float(width)
        metadata = forcing_mean.new_tensor([
            _duration_coordinate(width),
            _age_coordinate(low_lag, high_lag_exclusive),
        ]).expand(forcing_mean.shape[0], -1)
        pooled.append(torch.cat((forcing_mean, metadata), dim=-1))
    return {
        "recent": recent,
        "history": torch.stack(pooled, dim=1),
    }
