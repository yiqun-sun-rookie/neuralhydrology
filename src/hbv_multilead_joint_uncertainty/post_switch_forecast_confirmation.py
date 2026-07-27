"""Matched-block statistics for early post-switch forecasts."""

from __future__ import annotations

from typing import Mapping, Sequence

import numpy as np


_METHODS = ("full", "none", "uniform_independent")


def _bootstrap_interval(
    block_values: np.ndarray,
    bootstrap_indices: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    bootstrap_means = np.mean(block_values[bootstrap_indices], axis=1)
    return (
        np.mean(block_values, axis=0),
        np.percentile(bootstrap_means, 2.5, axis=0),
        np.percentile(bootstrap_means, 97.5, axis=0),
    )


def _paired_summary(
    full_squared_error: np.ndarray,
    baseline_squared_error: np.ndarray,
    bootstrap_indices: np.ndarray,
    minimum_meaningful_rmse_fraction: float,
) -> dict[str, np.ndarray]:
    difference = full_squared_error - baseline_squared_error
    block_mean = np.mean(difference, axis=(1, 2))
    mean, ci_low, ci_high = _bootstrap_interval(
        block_mean,
        bootstrap_indices,
    )
    baseline_mse = np.mean(
        baseline_squared_error,
        axis=(0, 1, 2),
    )
    improvement_multiplier = (
        (1.0 - minimum_meaningful_rmse_fraction) ** 2 - 1.0
    )
    improvement_boundary = baseline_mse * improvement_multiplier
    return {
        "squared_error_difference": difference,
        "block_mean": block_mean,
        "mean": mean,
        "ci_low": ci_low,
        "ci_high": ci_high,
        "baseline_mse": baseline_mse,
        "meaningful_improvement_boundary": improvement_boundary,
        "materially_improves": ci_high < improvement_boundary,
    }


def summarize_post_switch_forecasts(
    forecasts: Mapping[str, np.ndarray],
    truth_forecasts: np.ndarray,
    lead_days: Sequence[int] | np.ndarray,
    bootstrap_replicates: int,
    bootstrap_seed: int,
    minimum_meaningful_rmse_fraction: float,
) -> dict[str, object]:
    """Summarize fixed post-switch forecasts with matched-block intervals."""

    if set(forecasts) != set(_METHODS):
        raise ValueError(
            "forecasts must contain exactly full, none, and uniform_independent"
        )
    truth = np.asarray(truth_forecasts, dtype=np.float64)
    if (
        truth.ndim != 4
        or any(size == 0 for size in truth.shape)
        or truth.shape[-1] != 3
        or not np.all(np.isfinite(truth))
    ):
        raise ValueError(
            "truth forecasts must be finite [blocks, truths, origins, 3 leads]"
        )
    forecast_values: dict[str, np.ndarray] = {}
    for method in _METHODS:
        values = np.asarray(forecasts[method], dtype=np.float64)
        if values.shape != truth.shape:
            raise ValueError(f"{method} forecast shape must match truth")
        if not np.all(np.isfinite(values)):
            raise ValueError(f"{method} forecasts must be finite")
        forecast_values[method] = values
    leads = np.asarray(lead_days)
    if (
        leads.ndim != 1
        or not np.issubdtype(leads.dtype, np.integer)
        or tuple(int(value) for value in leads) != (1, 3, 7)
    ):
        raise ValueError("lead days must equal 1, 3, and 7")
    if (
        isinstance(bootstrap_replicates, bool)
        or not isinstance(bootstrap_replicates, (int, np.integer))
        or int(bootstrap_replicates) <= 0
    ):
        raise ValueError("bootstrap replicates must be a positive integer")
    if (
        isinstance(bootstrap_seed, bool)
        or not isinstance(bootstrap_seed, (int, np.integer))
    ):
        raise ValueError("bootstrap seed must be an integer")
    fraction = float(minimum_meaningful_rmse_fraction)
    if not np.isfinite(fraction) or not 0.0 < fraction < 1.0:
        raise ValueError(
            "minimum meaningful RMSE fraction must be between zero and one"
        )

    generator = np.random.default_rng(int(bootstrap_seed))
    bootstrap_indices = generator.integers(
        0,
        truth.shape[0],
        size=(int(bootstrap_replicates), truth.shape[0]),
        endpoint=False,
    )
    squared_errors = {
        method: np.square(values - truth)
        for method, values in forecast_values.items()
    }
    rmse = {
        method: np.sqrt(np.mean(values, axis=(0, 1, 2)))
        for method, values in squared_errors.items()
    }
    per_origin_rmse = {
        method: np.sqrt(np.mean(values, axis=(0, 1)))
        for method, values in squared_errors.items()
    }
    paired_none = _paired_summary(
        squared_errors["full"],
        squared_errors["none"],
        bootstrap_indices,
        fraction,
    )
    paired_uniform = _paired_summary(
        squared_errors["full"],
        squared_errors["uniform_independent"],
        bootstrap_indices,
        fraction,
    )
    gates = {
        "full_materially_improves_none_all_leads": bool(
            np.all(paired_none["materially_improves"])
        ),
        "full_materially_improves_uniform_independent_all_leads": bool(
            np.all(paired_uniform["materially_improves"])
        ),
    }
    gates["retain"] = bool(all(gates.values()))
    return {
        "methods": _METHODS,
        "lead_days": leads.astype(np.int64, copy=True),
        "squared_errors": squared_errors,
        "rmse": rmse,
        "per_origin_rmse": per_origin_rmse,
        "paired": {
            "full_minus_none": paired_none,
            "full_minus_uniform_independent": paired_uniform,
        },
        "bootstrap_indices": bootstrap_indices,
        "retention_gates": gates,
    }
