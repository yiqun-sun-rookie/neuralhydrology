"""All-day error audit for one combined posterior state per assimilation day.

This module deliberately has no parameter-switch-distance grouping.  The
candidate parameter vectors are fixed; posterior probabilities and their
weighted parameter summary may change each day.
"""

from __future__ import annotations

from typing import Sequence

import numpy as np

from hbv_joint_uncertainty.hbv_adapter import HYDRO_STATE_NAMES


def bootstrap_block_indices(
    block_count: int,
    replicates: int,
    seed: int,
) -> np.ndarray:
    """Return deterministic matched-block bootstrap indices."""

    if block_count <= 0:
        raise ValueError("block_count must be positive")
    if replicates <= 0:
        raise ValueError("replicates must be positive")
    return np.random.default_rng(int(seed)).integers(
        0,
        int(block_count),
        size=(int(replicates), int(block_count)),
        dtype=np.int64,
    )


def posterior_weighted_parameters(
    probabilities,
    parameter_vectors,
) -> np.ndarray:
    """Calculate one posterior-weighted parameter vector for every day."""

    weights = np.asarray(probabilities, dtype=np.float64)
    parameters = np.asarray(parameter_vectors, dtype=np.float64)
    if weights.ndim != 4 or weights.shape[-1] == 0:
        raise ValueError(
            "probabilities must have shape [blocks, truths, days, candidates]"
        )
    if parameters.ndim != 2 or parameters.shape[0] != weights.shape[-1]:
        raise ValueError(
            "parameter_vectors must have shape [candidates, parameters]"
        )
    if not np.all(np.isfinite(weights)) or np.any(weights < 0.0):
        raise ValueError("probabilities must be finite and nonnegative")
    if not np.all(np.isfinite(parameters)):
        raise ValueError("parameter_vectors must be finite")
    sums = np.sum(weights, axis=-1)
    if not np.allclose(sums, 1.0, rtol=0.0, atol=1e-12):
        raise ValueError("candidate probabilities must sum to one each day")
    normalized = weights / sums[..., None]
    return np.einsum("btdc,cp->btdp", normalized, parameters)


def summarize_daily_combined_state_error(
    method_states,
    truth_states,
    method_names: Sequence[str],
    bootstrap_indices,
    *,
    primary_method: str = "parameter_only",
    baseline_methods: Sequence[str] = ("fixed_filter", "open_loop"),
) -> dict[str, np.ndarray | tuple[str, ...]]:
    """Compare each day's unique combined state directly with that day's truth.

    The primary population is every assimilation day supplied in the arrays.
    Dependence is handled only through matched-block bootstrap resampling; no
    day is classified by distance from a synthetic truth-parameter change.
    """

    estimates = np.asarray(method_states, dtype=np.float64)
    truth = np.asarray(truth_states, dtype=np.float64)
    names = tuple(str(value) for value in method_names)
    if estimates.ndim != 5:
        raise ValueError(
            "method_states must have shape [blocks, truths, methods, days, states]"
        )
    if truth.ndim != 4:
        raise ValueError(
            "truth_states must have shape [blocks, truths, days, states]"
        )
    block_count, truth_count, method_count, day_count, state_count = (
        estimates.shape
    )
    if truth.shape != (block_count, truth_count, day_count, state_count):
        raise ValueError("truth_states must align exactly with method_states")
    if len(names) != method_count or len(set(names)) != method_count:
        raise ValueError("method_names must be unique and match the method axis")
    if state_count < len(HYDRO_STATE_NAMES):
        raise ValueError("state arrays do not contain all hydrologic states")
    if not np.all(np.isfinite(estimates)) or not np.all(np.isfinite(truth)):
        raise ValueError("state arrays must be finite")
    if primary_method not in names:
        raise ValueError("primary_method is absent from method_names")
    baselines = tuple(str(value) for value in baseline_methods)
    if not baselines or len(set(baselines)) != len(baselines):
        raise ValueError("baseline_methods must be nonempty and unique")
    if any(value not in names or value == primary_method for value in baselines):
        raise ValueError("each baseline must be a distinct available method")

    bootstrap = np.asarray(bootstrap_indices, dtype=np.int64)
    if bootstrap.ndim != 2 or bootstrap.shape[1] != block_count:
        raise ValueError(
            "bootstrap_indices must have shape [replicates, blocks]"
        )
    if bootstrap.shape[0] == 0 or np.any(bootstrap < 0) or np.any(
        bootstrap >= block_count
    ):
        raise ValueError("bootstrap_indices contain an invalid block index")

    selected_estimates = estimates[..., : len(HYDRO_STATE_NAMES)]
    selected_truth = truth[..., : len(HYDRO_STATE_NAMES)]
    errors = selected_estimates - selected_truth[:, :, None, :, :]
    squared_errors = np.square(errors)

    all_day_rmse = np.sqrt(np.mean(squared_errors, axis=(0, 1, 3)))
    daily_rmse = np.sqrt(np.mean(squared_errors, axis=(0, 1)))
    block_mse = np.mean(squared_errors, axis=(1, 3))
    truth_standard_deviation = np.std(selected_truth, axis=(0, 1, 2))
    if np.any(truth_standard_deviation <= 0.0):
        raise ValueError("each hydrologic truth state must vary over the audit")
    standardized_rmse = all_day_rmse / truth_standard_deviation[None, :]

    primary_index = names.index(primary_method)
    baseline_indices = np.asarray([names.index(value) for value in baselines])
    block_mse_difference = (
        block_mse[:, primary_index : primary_index + 1, :]
        - block_mse[:, baseline_indices, :]
    )
    bootstrap_differences = np.mean(
        block_mse_difference[bootstrap],
        axis=1,
    )
    mean_mse_difference = np.mean(block_mse_difference, axis=0)
    mse_difference_ci_low = np.quantile(
        bootstrap_differences, 0.025, axis=0
    )
    mse_difference_ci_high = np.quantile(
        bootstrap_differences, 0.975, axis=0
    )
    relative_rmse_fraction = (
        all_day_rmse[primary_index][None, :]
        / all_day_rmse[baseline_indices]
        - 1.0
    )

    return {
        "method_names": names,
        "state_names": tuple(HYDRO_STATE_NAMES),
        "primary_method": np.asarray(primary_method),
        "baseline_methods": baselines,
        "day_indices": np.arange(day_count, dtype=np.int64),
        "errors": errors,
        "all_day_rmse": all_day_rmse,
        "daily_rmse": daily_rmse,
        "block_mse": block_mse,
        "truth_standard_deviation": truth_standard_deviation,
        "standardized_rmse": standardized_rmse,
        "block_mse_difference": block_mse_difference,
        "mean_mse_difference": mean_mse_difference,
        "mse_difference_ci_low": mse_difference_ci_low,
        "mse_difference_ci_high": mse_difference_ci_high,
        "relative_rmse_fraction": relative_rmse_fraction,
        "bootstrap_indices": bootstrap.copy(),
    }
