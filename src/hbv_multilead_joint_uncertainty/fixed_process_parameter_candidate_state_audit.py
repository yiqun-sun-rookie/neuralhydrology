"""Same-day state audit for a single filter versus a standard full IMM.

No forecast operation belongs in this module.  Both state methods must come
from the same sealed assimilation run and share the same process covariance.
The three-model array is the unique global posterior from the fully
interacting multiple-model update, not a collection of final candidate states.
This completed comparison measures the two assimilation methods as wholes; it
does not isolate candidate count or the interaction operation by itself.
"""

from __future__ import annotations

from typing import Sequence

import numpy as np


CONTROLLED_STATE_METHODS = (
    "single_fixed_parameter_filter_state",
    "three_parameter_candidates_combined_state",
)
STATE_METHOD_ROLES = {
    CONTROLLED_STATE_METHODS[0]: "single_filter_posterior_state",
    CONTROLLED_STATE_METHODS[1]: (
        "fully_interacting_multiple_model_global_posterior_state"
    ),
}
STATE_GROUP_NAMES = ("hydrologic_stores", "routing_memory")
STATE_GROUP_SLICES = (slice(0, 5), slice(5, 15))


def _decision(ci_low, ci_high) -> np.ndarray:
    low = np.asarray(ci_low, dtype=np.float64)
    high = np.asarray(ci_high, dtype=np.float64)
    return np.where(
        high < 0.0,
        "improves",
        np.where(low > 0.0, "worsens", "inconclusive"),
    )


def summarize_complete_state_controlled_error(
    method_states,
    truth_states,
    method_names: Sequence[str],
    state_names: Sequence[str],
    bootstrap_indices,
) -> dict[str, object]:
    """Compare each method's final posterior state with same-day truth."""

    estimates = np.asarray(method_states, dtype=np.float64)
    truth = np.asarray(truth_states, dtype=np.float64)
    methods = tuple(str(value) for value in method_names)
    states = tuple(str(value) for value in state_names)
    if estimates.ndim != 5:
        raise ValueError(
            "method states must be [blocks, truths, methods, days, states]"
        )
    block_count, truth_count, method_count, day_count, state_count = estimates.shape
    if truth.shape != (block_count, truth_count, day_count, state_count):
        raise ValueError("truth states must align exactly with method states")
    if state_count != 15 or len(states) != 15:
        raise ValueError("complete-state audit requires exactly fifteen states")
    if len(set(states)) != 15:
        raise ValueError("state names must be unique")
    if methods != CONTROLLED_STATE_METHODS or method_count != 2:
        raise ValueError("method order differs from the controlled state contract")
    if not np.all(np.isfinite(estimates)) or not np.all(np.isfinite(truth)):
        raise ValueError("state arrays must be finite")

    bootstrap = np.asarray(bootstrap_indices, dtype=np.int64)
    if (
        bootstrap.ndim != 2
        or bootstrap.shape[0] == 0
        or bootstrap.shape[1] != block_count
        or np.any(bootstrap < 0)
        or np.any(bootstrap >= block_count)
    ):
        raise ValueError("bootstrap indices must contain valid matched blocks")

    truth_standard_deviation = np.std(truth, axis=(0, 1, 2))
    if np.any(~np.isfinite(truth_standard_deviation)) or np.any(
        truth_standard_deviation <= 0.0
    ):
        raise ValueError("each truth state must vary over the complete audit")

    errors = estimates - truth[:, :, None, :, :]
    squared = np.square(errors)
    standardized_squared = squared / np.square(
        truth_standard_deviation[None, None, None, None, :]
    )

    per_state_rmse = np.sqrt(np.mean(squared, axis=(0, 1, 3)))
    per_state_standardized_rmse = per_state_rmse / truth_standard_deviation[None, :]
    per_state_block_mse = np.mean(squared, axis=(1, 3))
    per_state_block_mse_difference = (
        per_state_block_mse[:, 1] - per_state_block_mse[:, 0]
    )
    per_state_bootstrap_difference = np.mean(
        per_state_block_mse_difference[bootstrap], axis=1
    )
    per_state_ci_low = np.quantile(
        per_state_bootstrap_difference, 0.025, axis=0
    )
    per_state_ci_high = np.quantile(
        per_state_bootstrap_difference, 0.975, axis=0
    )
    per_state_relative_rmse_fraction = per_state_rmse[1] / per_state_rmse[0] - 1.0

    group_raw_rmse = np.empty((2, 2), dtype=np.float64)
    group_standardized_rmse = np.empty((2, 2), dtype=np.float64)
    group_block_standardized_mse = np.empty((block_count, 2, 2), dtype=np.float64)
    for group_index, state_slice in enumerate(STATE_GROUP_SLICES):
        group_raw_rmse[:, group_index] = np.sqrt(
            np.mean(squared[..., state_slice], axis=(0, 1, 3, 4))
        )
        group_standardized_rmse[:, group_index] = np.sqrt(
            np.mean(
                standardized_squared[..., state_slice], axis=(0, 1, 3, 4)
            )
        )
        group_block_standardized_mse[:, :, group_index] = np.mean(
            standardized_squared[..., state_slice], axis=(1, 3, 4)
        )
    group_block_difference = (
        group_block_standardized_mse[:, 1] - group_block_standardized_mse[:, 0]
    )
    group_bootstrap_difference = np.mean(group_block_difference[bootstrap], axis=1)
    group_ci_low = np.quantile(group_bootstrap_difference, 0.025, axis=0)
    group_ci_high = np.quantile(group_bootstrap_difference, 0.975, axis=0)

    complete_standardized_rmse = np.sqrt(
        np.mean(standardized_squared, axis=(0, 1, 3, 4))
    )
    complete_block_standardized_mse = np.mean(
        standardized_squared, axis=(1, 3, 4)
    )
    complete_block_difference = (
        complete_block_standardized_mse[:, 1]
        - complete_block_standardized_mse[:, 0]
    )
    complete_bootstrap_difference = np.mean(
        complete_block_difference[bootstrap], axis=1
    )
    complete_ci_low = float(np.quantile(complete_bootstrap_difference, 0.025))
    complete_ci_high = float(np.quantile(complete_bootstrap_difference, 0.975))

    return {
        "method_names": methods,
        "method_roles": STATE_METHOD_ROLES.copy(),
        "state_names": states,
        "state_group_names": STATE_GROUP_NAMES,
        "day_indices": np.arange(day_count, dtype=np.int64),
        "truth_standard_deviation": truth_standard_deviation,
        "per_state_rmse": per_state_rmse,
        "per_state_standardized_rmse": per_state_standardized_rmse,
        "per_state_block_mse": per_state_block_mse,
        "per_state_block_mse_difference": per_state_block_mse_difference,
        "per_state_mean_mse_difference": np.mean(
            per_state_block_mse_difference, axis=0
        ),
        "per_state_ci_low": per_state_ci_low,
        "per_state_ci_high": per_state_ci_high,
        "per_state_relative_rmse_fraction": per_state_relative_rmse_fraction,
        "per_state_decision": _decision(per_state_ci_low, per_state_ci_high),
        "group_raw_rmse": group_raw_rmse,
        "group_standardized_rmse": group_standardized_rmse,
        "group_block_standardized_mse": group_block_standardized_mse,
        "group_block_standardized_mse_difference": group_block_difference,
        "group_standardized_mse_ci_low": group_ci_low,
        "group_standardized_mse_ci_high": group_ci_high,
        "group_relative_standardized_rmse_fraction": (
            group_standardized_rmse[1] / group_standardized_rmse[0] - 1.0
        ),
        "group_decision": _decision(group_ci_low, group_ci_high),
        "complete_standardized_rmse": complete_standardized_rmse,
        "complete_block_standardized_mse": complete_block_standardized_mse,
        "complete_block_standardized_mse_difference": complete_block_difference,
        "complete_standardized_mse_difference": float(
            np.mean(complete_block_difference)
        ),
        "complete_standardized_mse_ci_low": complete_ci_low,
        "complete_standardized_mse_ci_high": complete_ci_high,
        "complete_relative_standardized_rmse_fraction": float(
            complete_standardized_rmse[1] / complete_standardized_rmse[0] - 1.0
        ),
        "complete_decision": str(_decision(complete_ci_low, complete_ci_high).item()),
        "bootstrap_indices": bootstrap.copy(),
    }
