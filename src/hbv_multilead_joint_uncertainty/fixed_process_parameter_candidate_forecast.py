"""Forecast comparison for a single filter versus a standard full IMM.

The assimilation states come from a sealed experiment.  Both forecast arms
use the same process-noise candidate identifier, the same fixed parameter
vector, one final fifteen-element posterior state, and one direct deterministic
trajectory.  The three-model origin is the fully interacting method's unique
global posterior. Model-conditioned trajectories and covariances are outside
this module. The comparison does not isolate candidate count or interaction.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np


SEALED_METHODS = (
    "open_loop",
    "fixed_filter",
    "parameter_only",
    "noise_only",
    "joint",
)
SEALED_CANDIDATE_COUNTS = (1, 1, 3, 3, 9)
CONTROLLED_METHODS = (
    "single_fixed_parameter_filter_state",
    "three_parameter_candidates_combined_state",
)
CONTROLLED_METHOD_ROLES = {
    CONTROLLED_METHODS[0]: "single_filter_posterior_state",
    CONTROLLED_METHODS[1]: (
        "fully_interacting_multiple_model_global_posterior_state"
    ),
}
FIXED_FILTER_CANDIDATES = ("trained_center__process_2",)
PARAMETER_CANDIDATES = (
    "equifinal_diverse_1__process_2",
    "trained_center__process_2",
    "equifinal_diverse_2__process_2",
)
FIXED_PROCESS_ID = "process_2"
FIXED_FORECAST_PARAMETER_ID = "trained_center"


def _readonly(values, dtype=None) -> np.ndarray:
    result = np.array(values, dtype=dtype, copy=True)
    result.setflags(write=False)
    return result


@dataclass(frozen=True)
class ControlledCandidateContract:
    """Exact sealed candidate structure for the two controlled state sources."""

    output_method_names: tuple[str, str]
    source_method_names: tuple[str, str]
    source_method_indices: tuple[int, int]
    fixed_filter_candidates: tuple[str, ...]
    parameter_candidates: tuple[str, ...]
    parameter_candidate_parameter_ids: tuple[str, ...]
    parameter_candidate_process_ids: tuple[str, ...]
    fixed_process_id: str
    fixed_forecast_parameter_id: str


def _split_candidate_id(candidate_id: str) -> tuple[str, str]:
    pieces = str(candidate_id).rsplit("__", 1)
    if len(pieces) != 2 or not all(pieces):
        raise ValueError(f"invalid parameter-process candidate identifier: {candidate_id}")
    return pieces[0], pieces[1]


def validate_controlled_candidate_contract(
    method_names,
    method_candidate_ids,
    method_candidate_counts,
) -> ControlledCandidateContract:
    """Validate the archived single-filter versus full-IMM source methods.

    Matching process identifiers makes the overall method comparison cleaner,
    but the full-IMM arm also contains nontrivial interaction and probability
    combination. This validator therefore does not claim mechanism isolation.
    """

    names = tuple(str(value) for value in np.asarray(method_names).tolist())
    counts_array = np.asarray(method_candidate_counts)
    identifiers = np.asarray(method_candidate_ids)
    if names != SEALED_METHODS:
        raise ValueError("sealed method order differs from the frozen contract")
    if (
        counts_array.shape != (len(SEALED_METHODS),)
        or not np.issubdtype(counts_array.dtype, np.integer)
        or tuple(int(value) for value in counts_array) != SEALED_CANDIDATE_COUNTS
    ):
        raise ValueError("sealed candidate counts differ from the frozen contract")
    if identifiers.ndim != 2 or identifiers.shape[0] != len(SEALED_METHODS):
        raise ValueError("candidate identifiers must align with the sealed methods")
    if identifiers.shape[1] < max(SEALED_CANDIDATE_COUNTS):
        raise ValueError("candidate identifier matrix is incomplete")

    fixed_index = names.index("fixed_filter")
    parameter_index = names.index("parameter_only")
    fixed = tuple(
        str(value) for value in identifiers[fixed_index, : counts_array[fixed_index]]
    )
    parameter = tuple(
        str(value)
        for value in identifiers[parameter_index, : counts_array[parameter_index]]
    )
    if fixed != FIXED_FILTER_CANDIDATES:
        raise ValueError("fixed filter candidate differs from trained_center__process_2")

    fixed_parameter_ids, fixed_process_ids = zip(
        *(_split_candidate_id(value) for value in fixed)
    )
    parameter_ids, process_ids = zip(
        *(_split_candidate_id(value) for value in parameter)
    )
    if fixed_parameter_ids != (FIXED_FORECAST_PARAMETER_ID,):
        raise ValueError("fixed filter parameter candidate is not trained_center")
    if fixed_process_ids != (FIXED_PROCESS_ID,) or process_ids != (
        FIXED_PROCESS_ID,
    ) * 3:
        raise ValueError(
            "both assimilation methods must use the same process_2 process covariance"
        )
    expected_parameter_ids = tuple(
        _split_candidate_id(value)[0] for value in PARAMETER_CANDIDATES
    )
    if tuple(parameter_ids) != expected_parameter_ids:
        raise ValueError("three parameter candidates differ from the frozen contract")

    return ControlledCandidateContract(
        output_method_names=CONTROLLED_METHODS,
        source_method_names=("fixed_filter", "parameter_only"),
        source_method_indices=(fixed_index, parameter_index),
        fixed_filter_candidates=fixed,
        parameter_candidates=parameter,
        parameter_candidate_parameter_ids=tuple(parameter_ids),
        parameter_candidate_process_ids=tuple(process_ids),
        fixed_process_id=FIXED_PROCESS_ID,
        fixed_forecast_parameter_id=FIXED_FORECAST_PARAMETER_ID,
    )


def select_fixed_forecast_parameter(
    parameter_ids,
    parameter_vectors,
    parameter_id: str = FIXED_FORECAST_PARAMETER_ID,
) -> np.ndarray:
    """Select exactly one finite parameter vector by its frozen identifier."""

    identifiers = tuple(str(value) for value in np.asarray(parameter_ids).tolist())
    vectors = np.asarray(parameter_vectors, dtype=np.float64)
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("parameter identifiers must be unique")
    if vectors.ndim != 2 or vectors.shape[0] != len(identifiers):
        raise ValueError("parameter vectors must align with parameter identifiers")
    if not np.all(np.isfinite(vectors)):
        raise ValueError("parameter vectors must be finite")
    if parameter_id not in identifiers:
        raise ValueError(f"forecast parameter identifier is absent: {parameter_id}")
    return _readonly(vectors[identifiers.index(parameter_id)], np.float64)


def validate_common_forecast_parameters(left, right, trained_center) -> np.ndarray:
    """Require both methods to receive exactly the same trained-center vector."""

    left_values = np.asarray(left, dtype=np.float64)
    right_values = np.asarray(right, dtype=np.float64)
    expected = np.asarray(trained_center, dtype=np.float64)
    if (
        left_values.ndim != 1
        or right_values.shape != left_values.shape
        or expected.shape != left_values.shape
        or not np.all(np.isfinite(left_values))
        or not np.all(np.isfinite(right_values))
        or not np.all(np.isfinite(expected))
        or not np.array_equal(left_values, expected)
        or not np.array_equal(right_values, expected)
    ):
        raise ValueError("both methods must use the same trained_center forecast parameters")
    return _readonly(expected, np.float64)


def summarize_controlled_forecasts(
    forecasts: Mapping[str, np.ndarray],
    truth_forecasts,
    same_stage_mask,
    origin_stage_indices,
    stage_names: Sequence[str],
    bootstrap_indices,
    *,
    minimum_relative_rmse_reduction: float,
) -> dict[str, object]:
    """Compute all-stage primary and stage-specific matched forecast statistics."""

    if tuple(forecasts) != CONTROLLED_METHODS:
        raise ValueError("forecast methods must exactly match the frozen controlled order")
    truth = np.asarray(truth_forecasts, dtype=np.float64)
    if truth.ndim != 4 or not np.all(np.isfinite(truth)):
        raise ValueError("truth forecasts must be finite [blocks, truths, origins, leads]")
    block_count, truth_count, origin_count, lead_count = truth.shape
    mask = np.asarray(same_stage_mask, dtype=bool)
    if mask.shape != (truth_count, origin_count, lead_count):
        raise ValueError("same-stage mask must align with truth, origin, and lead axes")
    stages = np.asarray(origin_stage_indices)
    names = tuple(str(value) for value in stage_names)
    if (
        stages.shape != (truth_count, origin_count)
        or not np.issubdtype(stages.dtype, np.integer)
        or not names
        or len(names) != len(set(names))
        or np.any(stages < 0)
        or np.any(stages >= len(names))
    ):
        raise ValueError("origin stage indices must identify the supplied unique stages")
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
    stage_rmse = np.full(
        (len(CONTROLLED_METHODS), len(names), lead_count),
        np.nan,
        dtype=np.float64,
    )
    stage_sample_count_per_block = np.zeros(
        (len(names), lead_count), dtype=np.int64
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
            for stage in range(len(names)):
                stage_mask = selected_mask & (stages == stage)
                stage_sample_count_per_block[stage, lead] = int(np.sum(stage_mask))
                if np.any(stage_mask):
                    stage_rmse[method_index, stage, lead] = np.sqrt(
                        np.mean(squared[..., lead][:, stage_mask])
                    )

    block_difference = block_mse[1] - block_mse[0]
    bootstrap_mean_difference = np.mean(block_difference[bootstrap], axis=1)
    mean_difference = np.mean(block_difference, axis=0)
    ci_low = np.quantile(bootstrap_mean_difference, 0.025, axis=0)
    ci_high = np.quantile(bootstrap_mean_difference, 0.975, axis=0)
    relative = np.full(lead_count, np.nan, dtype=np.float64)
    stable = rmse[0] > 0.0
    relative[stable] = rmse[1, stable] / rmse[0, stable] - 1.0
    decision = np.isfinite(relative) & (relative <= -threshold) & (ci_high < 0.0)

    return {
        "method_names": CONTROLLED_METHODS,
        "stage_names": names,
        "same_stage_sample_count_per_block": np.sum(mask, axis=(0, 1)),
        "same_stage_sample_count_all_blocks": block_count * np.sum(mask, axis=(0, 1)),
        "stage_sample_count_per_block": stage_sample_count_per_block,
        "rmse": {
            method: rmse[index].copy()
            for index, method in enumerate(CONTROLLED_METHODS)
        },
        "block_mse": {
            method: block_mse[index].copy()
            for index, method in enumerate(CONTROLLED_METHODS)
        },
        "stage_rmse": stage_rmse,
        "squared_errors": squared_errors,
        "block_mse_difference": block_difference,
        "mean_mse_difference": mean_difference,
        "ci_low": ci_low,
        "ci_high": ci_high,
        "relative_rmse_fraction": relative,
        "improvement_decision": decision,
        "bootstrap_indices": bootstrap.copy(),
    }
