"""Rich causal inputs for medium and hierarchically grouped old history."""
from __future__ import annotations

import numpy as np
import torch

from bands_v03 import (
    BandSpec,
    _gather_daily,
    _validate_indices,
    fixed_band_specs_v03,
    lag_bin_edges,
)


def _chronological_bounds(spec: BandSpec) -> tuple[np.ndarray, np.ndarray]:
    edges = lag_bin_edges(spec)
    indices = np.arange(spec.bins - 1, -1, -1, dtype=np.int64)
    return edges[indices], edges[indices + 1]


def _gather_rich_blocks(
    x: torch.Tensor,
    basin_indices: torch.Tensor,
    target_indices: torch.Tensor,
    spec: BandSpec,
) -> torch.Tensor:
    low_lags_np, high_lags_np = _chronological_bounds(spec)
    low_lags = torch.as_tensor(low_lags_np, device=x.device, dtype=torch.long)
    high_lags = torch.as_tensor(high_lags_np, device=x.device, dtype=torch.long)
    widths = high_lags - low_lags
    max_width = int(widths.max())
    offsets = torch.arange(max_width, device=x.device)

    starts = target_indices[:, None] - high_lags[None, :] + 1
    times = starts[:, :, None] + offsets[None, None, :]
    valid = offsets[None, None, :] < widths[None, :, None]
    safe_times = torch.where(valid, times, starts[:, :, None])
    values = x[basin_indices[:, None, None], safe_times]
    mask = valid.unsqueeze(-1)
    counts = widths.to(dtype=x.dtype)[None, :, None]

    masked = torch.where(mask, values, torch.zeros_like(values))
    mean = masked.sum(dim=2) / counts
    deviations = torch.where(mask, values - mean.unsqueeze(2), torch.zeros_like(values))
    variance = deviations.square().sum(dim=2) / counts
    std = torch.sqrt(variance)
    minimum = torch.where(
        mask,
        values,
        torch.full_like(values, torch.inf),
    ).amin(dim=2)
    maximum = torch.where(
        mask,
        values,
        torch.full_like(values, -torch.inf),
    ).amax(dim=2)
    return torch.cat((mean, std, minimum, maximum), dim=-1)


def gather_rich_bands_v05(
    x: torch.Tensor,
    basin_indices: torch.Tensor,
    target_indices: torch.Tensor,
) -> dict[str, torch.Tensor]:
    """Return recent daily, medium rich, and five-by-twelve old rich inputs."""
    basin_indices, target_indices = _validate_indices(x, basin_indices, target_indices)
    recent, medium, old = fixed_band_specs_v03()
    old_tokens = _gather_rich_blocks(x, basin_indices, target_indices, old)
    return {
        "recent": _gather_daily(x, basin_indices, target_indices, recent),
        "medium": _gather_rich_blocks(x, basin_indices, target_indices, medium),
        "old": old_tokens.reshape(old_tokens.shape[0], 5, 12, old_tokens.shape[-1]),
    }
