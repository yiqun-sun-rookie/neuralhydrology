"""Causal continuous multiscale history extraction for version 08."""
from __future__ import annotations

import numpy as np
import torch

from bands_v03 import forcing_prefix


_RECENT_DAYS = 270
_HISTORY_START_LAG = 270
_HISTORY_END_EXCLUSIVE = 3650
_HISTORY_BINS = 120
_MIN_WIDTH = 6.0
_MAX_WIDTH = 78.0


def continuous_history_edges_v08() -> np.ndarray:
    """Return the frozen 121 edges for 120 gradually coarsened history bins."""
    edges = np.rint(
        np.exp(
            np.linspace(
                np.log(float(_HISTORY_START_LAG)),
                np.log(float(_HISTORY_END_EXCLUSIVE)),
                _HISTORY_BINS + 1,
            )
        )
    ).astype(np.int64)
    edges[0] = _HISTORY_START_LAG
    edges[-1] = _HISTORY_END_EXCLUSIVE
    if edges.shape != (_HISTORY_BINS + 1,) or np.any(np.diff(edges) <= 0):
        raise ValueError("history edges must be strictly increasing")
    if int(np.diff(edges).sum()) != _HISTORY_END_EXCLUSIVE - _HISTORY_START_LAG:
        raise ValueError("history edges do not cover the frozen lag interval")
    return edges


def _validate_inputs(
    forcing: torch.Tensor,
    prefix: torch.Tensor,
    basin_indices: torch.Tensor,
    target_indices: torch.Tensor,
) -> tuple[torch.Tensor, torch.Tensor]:
    if forcing.ndim != 3:
        raise ValueError("forcing must have shape [basin,time,feature]")
    if forcing.shape[-1] != 5:
        raise ValueError("forcing must contain exactly the five Maurer variables")
    if prefix.shape != (forcing.shape[0], forcing.shape[1] + 1, forcing.shape[2]):
        raise ValueError("prefix shape is not aligned with forcing")
    basin_indices = basin_indices.to(device=forcing.device, dtype=torch.long)
    target_indices = target_indices.to(device=forcing.device, dtype=torch.long)
    if basin_indices.ndim != 1 or target_indices.ndim != 1:
        raise ValueError("basin and target indices must be one-dimensional")
    if basin_indices.numel() == 0 or basin_indices.numel() != target_indices.numel():
        raise ValueError("basin and target indices must have the same nonzero length")
    if int(basin_indices.min()) < 0 or int(basin_indices.max()) >= forcing.shape[0]:
        raise IndexError("basin index is outside forcing")
    if int(target_indices.min()) < _HISTORY_END_EXCLUSIVE - 1:
        raise ValueError("target index must be at least 3649")
    if int(target_indices.max()) >= forcing.shape[1]:
        raise IndexError("target index is outside forcing")
    return basin_indices, target_indices


def _duration_coordinate(width: int) -> float:
    return float(
        (np.log(float(width)) - np.log(_MIN_WIDTH))
        / (np.log(_MAX_WIDTH) - np.log(_MIN_WIDTH))
    )


def _age_coordinate(low_lag: int, high_lag_exclusive: int) -> float:
    midpoint = 0.5 * (low_lag + high_lag_exclusive - 1)
    return float(
        (np.log(midpoint) - np.log(float(_HISTORY_START_LAG)))
        / (
            np.log(float(_HISTORY_END_EXCLUSIVE - 1))
            - np.log(float(_HISTORY_START_LAG))
        )
    )


def gather_continuous_history_v08(
    forcing: torch.Tensor,
    prefix: torch.Tensor,
    basin_indices: torch.Tensor,
    target_indices: torch.Tensor,
) -> dict[str, torch.Tensor]:
    """Extract recent daily forcing and one oldest-to-recent multiscale sequence."""
    basin_indices, target_indices = _validate_inputs(
        forcing,
        prefix,
        basin_indices,
        target_indices,
    )
    recent_lags = torch.arange(
        _RECENT_DAYS - 1,
        -1,
        -1,
        device=forcing.device,
    )
    recent_times = target_indices[:, None] - recent_lags[None, :]
    recent = forcing[basin_indices[:, None], recent_times]

    edges = continuous_history_edges_v08()
    pooled = []
    for edge_index in reversed(range(_HISTORY_BINS)):
        low_lag = int(edges[edge_index])
        high_lag_exclusive = int(edges[edge_index + 1])
        start = target_indices - high_lag_exclusive + 1
        end = target_indices - low_lag + 1
        total = prefix[basin_indices, end] - prefix[basin_indices, start]
        width = high_lag_exclusive - low_lag
        forcing_mean = total / float(width)
        metadata = forcing_mean.new_tensor(
            [
                _duration_coordinate(width),
                _age_coordinate(low_lag, high_lag_exclusive),
            ]
        ).expand(forcing_mean.shape[0], -1)
        pooled.append(torch.cat((forcing_mean, metadata), dim=-1))

    return {
        "recent": recent,
        "history": torch.stack(pooled, dim=1),
    }
