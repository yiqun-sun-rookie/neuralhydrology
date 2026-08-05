"""Deterministic forecasts from exactly one saved fifteen-element state.

This module is deliberately separate from the unscented-filter forecast path.
No covariance, sigma point, model probability, or future observation enters a
deterministic trajectory.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np

from hbv_joint_uncertainty.hbv_adapter import (
    HYDRO_STATE_NAMES,
    PARAMETER_NAMES,
    STATE_NAMES,
    routed_discharge,
)
from hbv_joint_uncertainty.preflight import ForcingTransition, project_hbv_state


STATE_SOURCES = (
    "posterior_all_states",
    "truth_all_states",
    "posterior_hydrologic_truth_routing",
    "truth_hydrologic_posterior_routing",
)
PARAMETER_SOURCES = (
    "true_stage_parameters",
    "posterior_weighted_parameters",
    "maximum_posterior_parameters",
)
PRIMARY_DETERMINISTIC_SINGLE_STATE_READOUT = (
    "posterior_all_states__posterior_weighted_parameters"
)
DETERMINISTIC_METHODS = tuple(
    f"{state_source}__{parameter_source}"
    for state_source in STATE_SOURCES
    for parameter_source in PARAMETER_SOURCES
)


def _readonly(values, dtype=None) -> np.ndarray:
    result = np.array(values, dtype=dtype, copy=True)
    result.setflags(write=False)
    return result


def _parameter_mapping(values) -> dict[str, float]:
    vector = np.asarray(values, dtype=np.float64)
    if vector.shape != (len(PARAMETER_NAMES),) or not np.all(np.isfinite(vector)):
        raise ValueError(
            f"parameter vector must contain {len(PARAMETER_NAMES)} finite values"
        )
    return {name: float(value) for name, value in zip(PARAMETER_NAMES, vector)}


@dataclass(frozen=True)
class AllStageDailyIndex:
    """All assimilation-day origins and their exact future targets."""

    lead_days: np.ndarray
    origin_indices: np.ndarray
    target_indices: np.ndarray
    origin_parameter_indices: np.ndarray
    target_parameter_indices: np.ndarray
    same_stage_mask: np.ndarray
    cross_switch_mask: np.ndarray


@dataclass(frozen=True)
class DeterministicForecast:
    """One direct HBV trajectory from one state and one parameter vector."""

    lead_days: np.ndarray
    discharge: np.ndarray
    states: np.ndarray


def build_all_stage_daily_index(
    truth_parameter_indices,
    *,
    assimilation_days: int = 540,
    lead_days: Sequence[int] = tuple(range(1, 8)),
) -> AllStageDailyIndex:
    """Return origins 0..539 and targets ``t+h`` through archived day 546."""

    schedule = np.asarray(truth_parameter_indices)
    if schedule.ndim != 2 or schedule.shape[0] == 0:
        raise ValueError("truth parameter indices must be a nonempty matrix")
    if not np.issubdtype(schedule.dtype, np.integer) or np.any(schedule < 0):
        raise ValueError("truth parameter indices must be nonnegative integers")
    if isinstance(assimilation_days, bool) or int(assimilation_days) != assimilation_days:
        raise ValueError("assimilation days must be an integer")
    day_count = int(assimilation_days)
    if day_count <= 0:
        raise ValueError("assimilation days must be positive")
    leads = np.asarray(tuple(lead_days))
    if (
        leads.ndim != 1
        or len(leads) == 0
        or not np.issubdtype(leads.dtype, np.integer)
        or np.any(leads <= 0)
        or np.any(np.diff(leads) <= 0)
    ):
        raise ValueError("lead days must be positive, unique, increasing integers")
    leads = leads.astype(np.int64, copy=False)
    origins = np.arange(day_count, dtype=np.int64)
    targets = origins[:, None] + leads[None, :]
    if int(np.max(targets)) >= schedule.shape[1]:
        raise ValueError("truth parameter schedule does not cover every forecast target")
    origin_parameters = schedule[:, origins]
    target_parameters = schedule[:, targets]
    same_stage = target_parameters == origin_parameters[:, :, None]
    return AllStageDailyIndex(
        lead_days=_readonly(leads, np.int64),
        origin_indices=_readonly(origins, np.int64),
        target_indices=_readonly(targets, np.int64),
        origin_parameter_indices=_readonly(origin_parameters, np.int64),
        target_parameter_indices=_readonly(target_parameters, np.int64),
        same_stage_mask=_readonly(same_stage, bool),
        cross_switch_mask=_readonly(~same_stage, bool),
    )


def forecast_deterministic_state(
    state,
    parameters,
    future_forcing,
    lead_days: Sequence[int] = tuple(range(1, 8)),
) -> DeterministicForecast:
    """Advance one state through one deterministic HBV trajectory."""

    state_values = np.asarray(state, dtype=np.float64)
    if state_values.shape != (len(STATE_NAMES),) or not np.all(np.isfinite(state_values)):
        raise ValueError(f"state must contain {len(STATE_NAMES)} finite values")
    parameter_values = _parameter_mapping(parameters)
    forcing = np.asarray(future_forcing, dtype=np.float64)
    if forcing.ndim != 2 or forcing.shape[1] != 3 or not np.all(np.isfinite(forcing)):
        raise ValueError("future forcing must be finite with shape [days, 3]")
    leads = np.asarray(tuple(lead_days))
    if (
        leads.ndim != 1
        or len(leads) == 0
        or not np.issubdtype(leads.dtype, np.integer)
        or np.any(leads <= 0)
        or np.any(np.diff(leads) <= 0)
    ):
        raise ValueError("lead days must be positive, unique, increasing integers")
    leads = leads.astype(np.int64, copy=False)
    if int(leads[-1]) > len(forcing):
        raise ValueError("future forcing does not cover the maximum lead")

    transition = ForcingTransition(parameter_values)
    current = project_hbv_state(state_values, parameter_values)
    selected_discharge = np.empty(len(leads), dtype=np.float64)
    selected_states = np.empty((len(leads), len(STATE_NAMES)), dtype=np.float64)
    lead_to_row = {int(lead): row for row, lead in enumerate(leads)}
    for step in range(1, int(leads[-1]) + 1):
        transition.set_forcing(*forcing[step - 1])
        current = transition(current)
        if step in lead_to_row:
            row = lead_to_row[step]
            selected_states[row] = current
            selected_discharge[row] = routed_discharge(
                current, parameter_values["lag_time"]
            )
    return DeterministicForecast(
        lead_days=leads.copy(),
        discharge=selected_discharge,
        states=selected_states,
    )


def build_factorial_state_sources(posterior_states, truth_states) -> dict[str, np.ndarray]:
    """Build complete and slice-replaced states for causal attribution."""

    posterior = np.asarray(posterior_states, dtype=np.float64)
    truth = np.asarray(truth_states, dtype=np.float64)
    if posterior.shape != truth.shape or posterior.ndim != 4:
        raise ValueError(
            "posterior and truth states must match [blocks, truths, origins, states]"
        )
    if posterior.shape[-1] != len(STATE_NAMES):
        raise ValueError(f"state arrays must contain {len(STATE_NAMES)} elements")
    if not np.all(np.isfinite(posterior)) or not np.all(np.isfinite(truth)):
        raise ValueError("state arrays must be finite")
    hydrologic_count = len(HYDRO_STATE_NAMES)
    posterior_hydrologic = truth.copy()
    posterior_hydrologic[..., :hydrologic_count] = posterior[..., :hydrologic_count]
    posterior_routing = truth.copy()
    posterior_routing[..., hydrologic_count:] = posterior[..., hydrologic_count:]
    return {
        "posterior_all_states": posterior.copy(),
        "truth_all_states": truth.copy(),
        "posterior_hydrologic_truth_routing": posterior_hydrologic,
        "truth_hydrologic_posterior_routing": posterior_routing,
    }


def summarize_complete_state_error(
    method_states,
    truth_states,
    method_names: Sequence[str],
) -> dict[str, np.ndarray | tuple[str, ...]]:
    """Summarize all fifteen state errors without switch-distance grouping."""

    estimates = np.asarray(method_states, dtype=np.float64)
    truth = np.asarray(truth_states, dtype=np.float64)
    names = tuple(str(value) for value in method_names)
    if estimates.ndim != 5:
        raise ValueError("method states must be [blocks, truths, methods, days, states]")
    if truth.shape != (
        estimates.shape[0], estimates.shape[1], estimates.shape[3], estimates.shape[4]
    ):
        raise ValueError("truth states must align exactly with method states")
    if estimates.shape[-1] != len(STATE_NAMES):
        raise ValueError(f"complete state requires {len(STATE_NAMES)} elements")
    if len(names) != estimates.shape[2] or len(set(names)) != len(names):
        raise ValueError("method names must uniquely match the method axis")
    if not np.all(np.isfinite(estimates)) or not np.all(np.isfinite(truth)):
        raise ValueError("state arrays must be finite")
    errors = estimates - truth[:, :, None, :, :]
    squared = np.square(errors)
    rmse = np.sqrt(np.mean(squared, axis=(0, 1, 3)))
    block_mse = np.mean(squared, axis=(1, 3))
    hydro_count = len(HYDRO_STATE_NAMES)
    group_rmse = np.column_stack(
        (
            np.sqrt(np.mean(squared[..., :hydro_count], axis=(0, 1, 3, 4))),
            np.sqrt(np.mean(squared[..., hydro_count:], axis=(0, 1, 3, 4))),
        )
    )
    return {
        "method_names": names,
        "state_names": tuple(STATE_NAMES),
        "state_group_names": ("hydrologic_stores", "routing_memory"),
        "errors": errors,
        "all_day_rmse": rmse,
        "block_mse": block_mse,
        "group_rmse": group_rmse,
    }


def summarize_deterministic_forecasts(
    forecasts: Mapping[str, np.ndarray],
    truth_forecasts,
    same_stage_mask,
    bootstrap_indices,
) -> dict[str, object]:
    """Compute matched-block forecast errors for every deterministic method."""

    if tuple(forecasts) != DETERMINISTIC_METHODS and set(forecasts) != set(DETERMINISTIC_METHODS):
        raise ValueError("forecasts must contain the frozen deterministic methods")
    truth = np.asarray(truth_forecasts, dtype=np.float64)
    if truth.ndim != 4 or not np.all(np.isfinite(truth)):
        raise ValueError("truth forecasts must be finite [blocks, truths, origins, leads]")
    mask = np.asarray(same_stage_mask, dtype=bool)
    if mask.shape != truth.shape[1:]:
        raise ValueError("same-stage mask must be [truths, origins, leads]")
    bootstrap = np.asarray(bootstrap_indices, dtype=np.int64)
    if (
        bootstrap.ndim != 2
        or bootstrap.shape[1] != truth.shape[0]
        or np.any(bootstrap < 0)
        or np.any(bootstrap >= truth.shape[0])
    ):
        raise ValueError("bootstrap indices must be [replicates, blocks]")

    squared_errors: dict[str, np.ndarray] = {}
    rmse: dict[str, np.ndarray] = {}
    block_mse: dict[str, np.ndarray] = {}
    for method in DETERMINISTIC_METHODS:
        values = np.asarray(forecasts[method], dtype=np.float64)
        if values.shape != truth.shape or not np.all(np.isfinite(values)):
            raise ValueError(f"forecast {method} must be finite and match truth")
        squared = np.square(values - truth)
        squared_errors[method] = squared
        method_rmse = np.empty(truth.shape[-1], dtype=np.float64)
        method_block_mse = np.empty((truth.shape[0], truth.shape[-1]), dtype=np.float64)
        for lead in range(truth.shape[-1]):
            selected_mask = mask[..., lead]
            selected = squared[..., lead][:, selected_mask]
            method_rmse[lead] = np.sqrt(np.mean(selected))
            method_block_mse[:, lead] = np.mean(selected, axis=1)
        rmse[method] = method_rmse
        block_mse[method] = method_block_mse

    comparisons: dict[str, dict[str, np.ndarray]] = {}
    for left, right in (
        (
            "truth_all_states__true_stage_parameters",
            "posterior_all_states__true_stage_parameters",
        ),
        (
            "posterior_all_states__true_stage_parameters",
            "posterior_all_states__posterior_weighted_parameters",
        ),
        (
            "posterior_hydrologic_truth_routing__true_stage_parameters",
            "posterior_all_states__true_stage_parameters",
        ),
        (
            "truth_hydrologic_posterior_routing__true_stage_parameters",
            "posterior_all_states__true_stage_parameters",
        ),
    ):
        difference = block_mse[left] - block_mse[right]
        bootstrap_mean = np.mean(difference[bootstrap], axis=1)
        comparisons[f"{left}__minus__{right}"] = {
            "block_mean_mse_difference": difference,
            "mean_mse_difference": np.mean(difference, axis=0),
            "ci_low": np.quantile(bootstrap_mean, 0.025, axis=0),
            "ci_high": np.quantile(bootstrap_mean, 0.975, axis=0),
            "left_rmse": rmse[left].copy(),
            "right_rmse": rmse[right].copy(),
            "relative_rmse_fraction": rmse[left] / rmse[right] - 1.0,
        }
    return {
        "method_names": DETERMINISTIC_METHODS,
        "same_stage_sample_count": np.sum(mask, axis=(0, 1)),
        "squared_errors": squared_errors,
        "rmse": rmse,
        "block_mse": block_mse,
        "comparisons": comparisons,
        "bootstrap_indices": bootstrap.copy(),
    }
