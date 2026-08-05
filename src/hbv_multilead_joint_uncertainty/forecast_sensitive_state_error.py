"""Marginal forecast effects of correcting one saved state component at a time."""

from __future__ import annotations

from collections.abc import Mapping, Sequence

import numpy as np

from hbv_joint_uncertainty.hbv_adapter import (
    HYDRO_STATE_NAMES,
    ROUTING_STATE_NAMES,
    STATE_NAMES,
)


STATE_METHODS = ("parameter_only", "joint")
BASELINE_INTERVENTION = "baseline_estimated"
COMPONENT_INTERVENTIONS = tuple(
    f"truth_component__{name}" for name in STATE_NAMES
)
GROUP_INTERVENTIONS = (
    "truth_hydrologic_group",
    "truth_routing_group",
    "truth_all_states",
)
INTERVENTION_NAMES = (
    BASELINE_INTERVENTION,
    *COMPONENT_INTERVENTIONS,
    *GROUP_INTERVENTIONS,
)


def build_state_interventions(estimated_state, truth_state) -> dict[str, np.ndarray]:
    """Return frozen marginal truth replacements for one complete state array."""

    estimated = np.asarray(estimated_state, dtype=np.float64)
    truth = np.asarray(truth_state, dtype=np.float64)
    if estimated.shape != truth.shape or estimated.ndim < 1:
        raise ValueError("estimated and truth states must have the same shape")
    if estimated.shape[-1] != len(STATE_NAMES):
        raise ValueError(f"complete states must contain {len(STATE_NAMES)} elements")
    if not np.all(np.isfinite(estimated)) or not np.all(np.isfinite(truth)):
        raise ValueError("state arrays must contain only finite values")

    interventions = {BASELINE_INTERVENTION: estimated.copy()}
    for index, name in enumerate(STATE_NAMES):
        corrected = estimated.copy()
        corrected[..., index] = truth[..., index]
        interventions[f"truth_component__{name}"] = corrected

    hydrologic_count = len(HYDRO_STATE_NAMES)
    hydrologic = estimated.copy()
    hydrologic[..., :hydrologic_count] = truth[..., :hydrologic_count]
    routing = estimated.copy()
    routing[..., hydrologic_count:] = truth[..., hydrologic_count:]
    interventions["truth_hydrologic_group"] = hydrologic
    interventions["truth_routing_group"] = routing
    interventions["truth_all_states"] = truth.copy()
    if tuple(interventions) != INTERVENTION_NAMES:
        raise RuntimeError("state intervention order changed")
    return interventions


def summarize_intervention_forecasts(
    forecasts: Mapping[str, Mapping[str, np.ndarray]],
    truth_forecasts,
    same_stage_mask,
    bootstrap_indices,
    method_names: Sequence[str] = STATE_METHODS,
    intervention_names: Sequence[str] = INTERVENTION_NAMES,
    *,
    minimum_relative_rmse_reduction: float = 0.01,
) -> dict[str, np.ndarray | tuple[str, ...]]:
    """Summarize paired marginal effects relative to each method's baseline."""

    methods = tuple(str(value) for value in method_names)
    interventions = tuple(str(value) for value in intervention_names)
    if methods != STATE_METHODS:
        raise ValueError("state method order differs from the frozen contract")
    if interventions != INTERVENTION_NAMES:
        raise ValueError("intervention order differs from the frozen contract")
    truth = np.asarray(truth_forecasts, dtype=np.float64)
    mask = np.asarray(same_stage_mask, dtype=bool)
    bootstrap = np.asarray(bootstrap_indices, dtype=np.int64)
    if truth.ndim != 4 or not np.all(np.isfinite(truth)):
        raise ValueError("truth forecasts must be finite [blocks, truths, origins, leads]")
    if mask.shape != truth.shape[1:]:
        raise ValueError("same-stage mask must be [truths, origins, leads]")
    if (
        bootstrap.ndim != 2
        or bootstrap.shape[1] != truth.shape[0]
        or np.any(bootstrap < 0)
        or np.any(bootstrap >= truth.shape[0])
    ):
        raise ValueError("bootstrap indices must be [replicates, blocks]")
    threshold = float(minimum_relative_rmse_reduction)
    if not np.isfinite(threshold) or threshold < 0.0:
        raise ValueError("minimum relative RMSE reduction must be nonnegative")

    method_count = len(methods)
    intervention_count = len(interventions)
    block_count = truth.shape[0]
    lead_count = truth.shape[-1]
    rmse = np.empty((method_count, intervention_count, lead_count), dtype=np.float64)
    block_mse = np.empty(
        (method_count, intervention_count, block_count, lead_count),
        dtype=np.float64,
    )
    for method_index, method in enumerate(methods):
        if method not in forecasts or tuple(forecasts[method]) != interventions:
            raise ValueError(f"forecast interventions changed for {method}")
        for intervention_index, intervention in enumerate(interventions):
            values = np.asarray(forecasts[method][intervention], dtype=np.float64)
            if values.shape != truth.shape or not np.all(np.isfinite(values)):
                raise ValueError(
                    f"forecast {method}/{intervention} must be finite and match truth"
                )
            squared = np.square(values - truth)
            for lead in range(lead_count):
                selected = squared[..., lead][:, mask[..., lead]]
                rmse[method_index, intervention_index, lead] = np.sqrt(
                    np.mean(selected)
                )
                block_mse[method_index, intervention_index, :, lead] = np.mean(
                    selected, axis=1
                )

    baseline_index = interventions.index(BASELINE_INTERVENTION)
    difference = block_mse - block_mse[:, baseline_index : baseline_index + 1]
    mean_difference = np.mean(difference, axis=2)
    bootstrap_mean = np.mean(difference[:, :, bootstrap, :], axis=3)
    ci_low = np.quantile(bootstrap_mean, 0.025, axis=2)
    ci_high = np.quantile(bootstrap_mean, 0.975, axis=2)
    baseline_rmse = rmse[:, baseline_index : baseline_index + 1]
    relative_rmse_change = rmse / baseline_rmse - 1.0
    material_contributor = (
        (relative_rmse_change <= -threshold) & (ci_high < 0.0)
    )
    material_harmful = (
        (relative_rmse_change >= threshold) & (ci_low > 0.0)
    )
    material_contributor[:, baseline_index] = False
    material_harmful[:, baseline_index] = False

    component_slice = slice(1, 1 + len(COMPONENT_INTERVENTIONS))
    component_order = np.argsort(rmse[:, component_slice, :], axis=1)
    component_ranking = np.asarray(COMPONENT_INTERVENTIONS, dtype=str)[
        component_order
    ]
    return {
        "method_names": methods,
        "intervention_names": interventions,
        "state_names": tuple(STATE_NAMES),
        "same_stage_sample_count": np.sum(mask, axis=(0, 1)),
        "rmse": rmse,
        "block_mse": block_mse,
        "block_mse_difference_from_baseline": difference,
        "mean_mse_difference_from_baseline": mean_difference,
        "ci_low": ci_low,
        "ci_high": ci_high,
        "relative_rmse_change": relative_rmse_change,
        "material_contributor": material_contributor,
        "material_harmful": material_harmful,
        "component_ranking": component_ranking,
        "bootstrap_indices": bootstrap.copy(),
    }
