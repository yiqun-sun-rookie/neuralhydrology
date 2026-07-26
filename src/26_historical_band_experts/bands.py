"""Causal extraction of the three frozen historical input bands."""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import torch


@dataclass(frozen=True)
class BandSpec:
    """One inclusive lag interval and its fixed output resolution."""

    name: str
    start_lag: int
    end_lag: int
    bins: int


def fixed_band_specs() -> tuple[BandSpec, ...]:
    """Return the preregistered, disjoint 3650-day input bands."""
    return (
        BandSpec("recent", 0, 29, 30),
        BandSpec("medium", 30, 1824, 60),
        BandSpec("old", 1825, 3649, 60),
    )


def lag_bin_edges(spec: BandSpec) -> np.ndarray:
    """Integer lag-bin edges covering every lag in the specification exactly once."""
    length = spec.end_lag - spec.start_lag + 1
    if spec.bins <= 0 or spec.bins > length:
        raise ValueError(f"invalid bin count {spec.bins} for interval length {length}")
    base, remainder = divmod(length, spec.bins)
    widths = np.full(spec.bins, base, dtype=np.int64)
    widths[:remainder] += 1
    return np.concatenate((
        np.asarray([spec.start_lag], dtype=np.int64),
        spec.start_lag + np.cumsum(widths, dtype=np.int64),
    ))


def _validate_indices(
    x: torch.Tensor,
    basin_indices: torch.Tensor,
    target_indices: torch.Tensor,
) -> tuple[torch.Tensor, torch.Tensor]:
    if x.ndim != 3:
        raise ValueError(f"x must have shape [basin,time,feature], got {tuple(x.shape)}")
    basin_indices = basin_indices.to(device=x.device, dtype=torch.long)
    target_indices = target_indices.to(device=x.device, dtype=torch.long)
    if basin_indices.ndim != 1 or target_indices.ndim != 1:
        raise ValueError("basin_indices and target_indices must be one-dimensional")
    if basin_indices.numel() != target_indices.numel():
        raise ValueError("basin_indices and target_indices must have the same length")
    if basin_indices.numel() == 0:
        raise ValueError("at least one sample is required")
    if int(basin_indices.min()) < 0 or int(basin_indices.max()) >= x.shape[0]:
        raise IndexError("basin index is outside x")
    required_history = max(spec.end_lag for spec in fixed_band_specs())
    if int(target_indices.min()) < required_history:
        raise ValueError(f"target index must be at least {required_history}")
    if int(target_indices.max()) >= x.shape[1]:
        raise IndexError("target index is outside x")
    return basin_indices, target_indices


def _gather_daily(
    x: torch.Tensor,
    basin_indices: torch.Tensor,
    target_indices: torch.Tensor,
    spec: BandSpec,
) -> torch.Tensor:
    lags = torch.arange(spec.end_lag, spec.start_lag - 1, -1, device=x.device)
    time_indices = target_indices[:, None] - lags[None, :]
    return x[basin_indices[:, None], time_indices]


def _gather_pooled(
    prefix: torch.Tensor,
    basin_indices: torch.Tensor,
    target_indices: torch.Tensor,
    spec: BandSpec,
) -> torch.Tensor:
    edges = lag_bin_edges(spec)
    pooled = []
    for index in reversed(range(spec.bins)):
        low_lag = int(edges[index])
        high_lag_exclusive = int(edges[index + 1])
        start = target_indices - high_lag_exclusive + 1
        end = target_indices - low_lag + 1
        total = prefix[basin_indices, end] - prefix[basin_indices, start]
        pooled.append(total / float(high_lag_exclusive - low_lag))
    return torch.stack(pooled, dim=1)

def forcing_prefix(x: torch.Tensor) -> torch.Tensor:
    """Build one reusable cumulative forcing tensor."""
    if x.ndim != 3:
        raise ValueError(f"x must have shape [basin,time,feature], got {tuple(x.shape)}")
    return torch.cat(
        (x.new_zeros((x.shape[0], 1, x.shape[2])), torch.cumsum(x, dim=1)),
        dim=1,
    )


def gather_fixed_bands(
    x: torch.Tensor,
    basin_indices: torch.Tensor,
    target_indices: torch.Tensor,
    prefix: torch.Tensor | None = None,
) -> dict[str, torch.Tensor]:
    """Extract causal recent daily and older pooled inputs in chronological order."""
    basin_indices, target_indices = _validate_indices(x, basin_indices, target_indices)
    specs = fixed_band_specs()
    if prefix is None:
        prefix = forcing_prefix(x)
    if prefix.shape != (x.shape[0], x.shape[1] + 1, x.shape[2]):
        raise ValueError("prefix shape is not aligned with x")
    return {
        specs[0].name: _gather_daily(x, basin_indices, target_indices, specs[0]),
        specs[1].name: _gather_pooled(prefix, basin_indices, target_indices, specs[1]),
        specs[2].name: _gather_pooled(prefix, basin_indices, target_indices, specs[2]),
    }
