"""Paired statistics for the HBV state-interaction forecast control.

The two inputs are deterministic forecasts from each assimilation method's
single global posterior state.  The signed comparison is always full
state-and-covariance interaction minus no state interaction.
"""

from __future__ import annotations

from typing import Mapping

import numpy as np


CONTROLLED_METHODS = (
    "fully_interacting_global_posterior_state",
    "noninteracting_global_posterior_state",
)
DIFFERENCE_DEFINITION = "full_interaction_minus_no_interaction"


def summarize_state_interaction_forecasts(
    forecasts: Mapping[str, np.ndarray],
    truth_forecasts,
    same_stage_mask,
    bootstrap_indices,
    *,
    minimum_relative_rmse_reduction: float,
) -> dict[str, object]:
    """Summarize matched full-stage forecasts for lead days one through seven."""

    if tuple(forecasts) != CONTROLLED_METHODS:
        raise ValueError("forecast methods must exactly match the frozen method order")
    truth = np.asarray(truth_forecasts, dtype=np.float64)
    if truth.ndim != 4 or not np.all(np.isfinite(truth)):
        raise ValueError(
            "truth forecasts must be finite [blocks, truths, origins, leads]"
        )
    block_count, truth_count, origin_count, lead_count = truth.shape
    mask = np.asarray(same_stage_mask, dtype=bool)
    if mask.shape != (truth_count, origin_count, lead_count):
        raise ValueError("same-stage mask must align with truth, origin, and lead axes")
    bootstrap = np.asarray(bootstrap_indices, dtype=np.int64)
    if (
        bootstrap.ndim != 2
        or bootstrap.shape[0] == 0
        or bootstrap.shape[1] != block_count
        or np.any(bootstrap < 0)
        or np.any(bootstrap >= block_count)
    ):
        raise ValueError("bootstrap indices must contain valid matched blocks")
    threshold = float(minimum_relative_rmse_reduction)
    if not np.isfinite(threshold) or threshold < 0.0:
        raise ValueError("minimum relative root-mean-square-error reduction is invalid")

    rmse = np.empty((len(CONTROLLED_METHODS), lead_count), dtype=np.float64)
    block_mse = np.empty(
        (len(CONTROLLED_METHODS), block_count, lead_count), dtype=np.float64
    )
    squared_errors: dict[str, np.ndarray] = {}
    for method_index, method in enumerate(CONTROLLED_METHODS):
        values = np.asarray(forecasts[method], dtype=np.float64)
        if values.shape != truth.shape or not np.all(np.isfinite(values)):
            raise ValueError(f"forecast {method} must be finite and match truth")
        squared = np.square(values - truth)
        squared_errors[method] = squared
        for lead in range(lead_count):
            selected_mask = mask[..., lead]
            if not np.any(selected_mask):
                raise ValueError("every lead must retain at least one same-stage target")
            selected = squared[..., lead][:, selected_mask]
            rmse[method_index, lead] = np.sqrt(np.mean(selected))
            block_mse[method_index, :, lead] = np.mean(selected, axis=1)

    block_difference = block_mse[0] - block_mse[1]
    bootstrap_mean_difference = np.mean(block_difference[bootstrap], axis=1)
    mean_difference = np.mean(block_difference, axis=0)
    ci_low = np.quantile(bootstrap_mean_difference, 0.025, axis=0)
    ci_high = np.quantile(bootstrap_mean_difference, 0.975, axis=0)
    relative = np.full(lead_count, np.nan, dtype=np.float64)
    valid_denominator = rmse[1] > 0.0
    relative[valid_denominator] = (
        rmse[0, valid_denominator] / rmse[1, valid_denominator] - 1.0
    )
    decision = np.isfinite(relative) & (relative <= -threshold) & (ci_high < 0.0)

    return {
        "method_names": CONTROLLED_METHODS,
        "difference_definition": DIFFERENCE_DEFINITION,
        "same_stage_sample_count_per_block": np.sum(mask, axis=(0, 1)),
        "same_stage_sample_count_all_blocks": block_count
        * np.sum(mask, axis=(0, 1)),
        "rmse": {
            method: rmse[index].copy()
            for index, method in enumerate(CONTROLLED_METHODS)
        },
        "block_mse": {
            method: block_mse[index].copy()
            for index, method in enumerate(CONTROLLED_METHODS)
        },
        "squared_errors": squared_errors,
        "block_mse_difference": block_difference,
        "mean_mse_difference": mean_difference,
        "ci_low": ci_low,
        "ci_high": ci_high,
        "relative_rmse_fraction": relative,
        "improvement_decision": decision,
        "bootstrap_indices": bootstrap.copy(),
    }
