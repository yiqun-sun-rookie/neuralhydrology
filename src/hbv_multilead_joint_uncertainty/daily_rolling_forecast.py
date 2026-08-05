"""Full-stage daily rolling forecast indexing and matched-block statistics."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np


_METHODS = ("full", "none", "uniform_independent")
_TIME_STRATA = (
    ("days_000_006", 0, 6),
    ("days_007_029", 7, 29),
    ("days_030_089", 30, 89),
    ("days_090_179", 90, 179),
)


def _readonly(values, dtype=None) -> np.ndarray:
    result = np.array(values, dtype=dtype, copy=True)
    result.setflags(write=False)
    return result


def _integer_vector(
    values: Sequence[int] | np.ndarray,
    name: str,
    *,
    strictly_increasing: bool,
) -> np.ndarray:
    array = np.asarray(values)
    if (
        array.ndim != 1
        or len(array) == 0
        or not np.issubdtype(array.dtype, np.integer)
    ):
        raise ValueError(f"{name} must be a nonempty integer vector")
    array = array.astype(np.int64, copy=False)
    if np.any(array <= 0):
        raise ValueError(f"{name} must be positive")
    if strictly_increasing and np.any(np.diff(array) <= 0):
        raise ValueError(f"{name} must be strictly increasing")
    return array


@dataclass(frozen=True)
class DailyRollingIndex:
    """Immutable lead-specific sample definition for daily rolling forecasts."""

    lead_days: np.ndarray
    origin_indices: np.ndarray
    target_indices: np.ndarray
    origin_stage_indices: np.ndarray
    target_stage_indices: np.ndarray
    days_since_switch: np.ndarray
    same_stage_mask: np.ndarray
    cross_switch_mask: np.ndarray
    unavailable_mask: np.ndarray


def build_daily_rolling_index(
    *,
    stage_lengths: Sequence[int] | np.ndarray = (180, 180, 180),
    switch_days: Sequence[int] | np.ndarray = (180, 360),
    lead_days: Sequence[int] | np.ndarray = tuple(range(1, 8)),
) -> DailyRollingIndex:
    """Build the frozen three-stage daily rolling forecast sample definition."""

    stages = _integer_vector(
        stage_lengths,
        "stage lengths",
        strictly_increasing=False,
    )
    if len(stages) != 3:
        raise ValueError("daily rolling design requires exactly three stages")
    if tuple(int(value) for value in stages) != (180, 180, 180):
        raise ValueError("stage lengths must equal 180, 180, and 180")
    switches = _integer_vector(
        switch_days,
        "switch days",
        strictly_increasing=True,
    )
    expected_switches = np.cumsum(stages)[:-1]
    if not np.array_equal(switches, expected_switches):
        raise ValueError("switch days must equal cumulative stage boundaries")
    leads = _integer_vector(
        lead_days,
        "lead days",
        strictly_increasing=True,
    )
    if tuple(int(value) for value in leads) != tuple(range(1, 8)):
        raise ValueError("lead days must equal 1 through 7")

    total_days = int(np.sum(stages))
    origins = np.arange(int(switches[0]), total_days, dtype=np.int64)
    targets = origins[:, None] + leads[None, :]
    available = targets < total_days
    origin_stages = np.searchsorted(
        switches,
        origins,
        side="right",
    ).astype(np.int64)
    target_stages = np.full(targets.shape, -1, dtype=np.int64)
    target_stages[available] = np.searchsorted(
        switches,
        targets[available],
        side="right",
    )
    same_stage = available & (
        target_stages == origin_stages[:, None]
    )
    cross_switch = available & (
        target_stages > origin_stages[:, None]
    )
    unavailable = ~available
    last_switch = switches[origin_stages - 1]
    offsets = origins - last_switch

    return DailyRollingIndex(
        lead_days=_readonly(leads, np.int64),
        origin_indices=_readonly(origins, np.int64),
        target_indices=_readonly(targets, np.int64),
        origin_stage_indices=_readonly(origin_stages, np.int64),
        target_stage_indices=_readonly(target_stages, np.int64),
        days_since_switch=_readonly(offsets, np.int64),
        same_stage_mask=_readonly(same_stage, bool),
        cross_switch_mask=_readonly(cross_switch, bool),
        unavailable_mask=_readonly(unavailable, bool),
    )


def _masked_rmse(
    squared_error: np.ndarray,
    mask: np.ndarray,
) -> np.ndarray:
    lead_count = squared_error.shape[-1]
    result = np.empty(lead_count, dtype=np.float64)
    for lead_index in range(lead_count):
        selected = squared_error[
            :,
            :,
            mask[:, lead_index],
            lead_index,
        ]
        if selected.size == 0:
            raise ValueError("each lead must have at least one selected sample")
        result[lead_index] = np.sqrt(np.mean(selected))
    return result


def _block_mse(
    squared_error: np.ndarray,
    mask: np.ndarray,
) -> np.ndarray:
    block_count = squared_error.shape[0]
    lead_count = squared_error.shape[-1]
    result = np.empty((block_count, lead_count), dtype=np.float64)
    for lead_index in range(lead_count):
        selected = squared_error[
            :,
            :,
            mask[:, lead_index],
            lead_index,
        ]
        if selected.shape[2] == 0:
            raise ValueError("each lead must have at least one selected origin")
        result[:, lead_index] = np.mean(selected, axis=(1, 2))
    return result


def _paired_summary(
    full_block_mse: np.ndarray,
    baseline_block_mse: np.ndarray,
    bootstrap_indices: np.ndarray,
    minimum_meaningful_rmse_fraction: float,
) -> dict[str, np.ndarray]:
    difference = full_block_mse - baseline_block_mse
    bootstrap_means = np.mean(
        difference[bootstrap_indices],
        axis=1,
    )
    baseline_mse = np.mean(baseline_block_mse, axis=0)
    boundary = baseline_mse * (
        (1.0 - minimum_meaningful_rmse_fraction) ** 2 - 1.0
    )
    ci_low = np.percentile(bootstrap_means, 2.5, axis=0)
    ci_high = np.percentile(bootstrap_means, 97.5, axis=0)
    return {
        "block_mean": difference,
        "mean": np.mean(difference, axis=0),
        "ci_low": ci_low,
        "ci_high": ci_high,
        "baseline_mse": baseline_mse,
        "meaningful_improvement_boundary": boundary,
        "materially_improves": ci_high < boundary,
    }


def _stratified_rmse(
    squared_errors: Mapping[str, np.ndarray],
    index: DailyRollingIndex,
    minimum_offset: int,
    maximum_offset: int,
) -> dict[str, object]:
    offset_mask = (
        (index.days_since_switch >= minimum_offset)
        & (index.days_since_switch <= maximum_offset)
    )
    mask = index.same_stage_mask & offset_mask[:, None]
    return {
        "minimum_offset": int(minimum_offset),
        "maximum_offset": int(maximum_offset),
        "sample_count_per_block_truth": np.sum(mask, axis=0),
        "rmse": {
            method: _masked_rmse(values, mask)
            for method, values in squared_errors.items()
        },
    }


def _daily_offset_summary(
    squared_errors: Mapping[str, np.ndarray],
    index: DailyRollingIndex,
) -> dict[str, object]:
    offsets = np.arange(180, dtype=np.int64)
    lead_count = len(index.lead_days)
    sample_count = np.zeros((len(offsets), lead_count), dtype=np.int64)
    rmse = {
        method: np.zeros((len(offsets), lead_count), dtype=np.float64)
        for method in _METHODS
    }
    for offset in offsets:
        mask = index.same_stage_mask & (
            index.days_since_switch == offset
        )[:, None]
        sample_count[offset] = np.sum(mask, axis=0)
        for lead_index in range(lead_count):
            if sample_count[offset, lead_index] == 0:
                continue
            for method in _METHODS:
                values = squared_errors[method][
                    :,
                    :,
                    mask[:, lead_index],
                    lead_index,
                ]
                rmse[method][offset, lead_index] = np.sqrt(np.mean(values))
    return {
        "offset_days": offsets,
        "sample_count": {
            method: sample_count.copy()
            for method in _METHODS
        },
        "rmse": rmse,
    }


def summarize_daily_rolling_forecasts(
    forecasts: Mapping[str, np.ndarray],
    truth_forecasts: np.ndarray,
    index: DailyRollingIndex,
    *,
    bootstrap_replicates: int,
    bootstrap_seed: int,
    minimum_meaningful_rmse_fraction: float,
) -> dict[str, object]:
    """Summarize same-stage forecasts while preserving matched-block dependence."""

    if tuple(forecasts) != _METHODS and set(forecasts) != set(_METHODS):
        raise ValueError(
            "forecasts must contain full, none, and uniform_independent"
        )
    truth = np.asarray(truth_forecasts, dtype=np.float64)
    expected_tail = (
        len(index.origin_indices),
        len(index.lead_days),
    )
    if (
        truth.ndim != 4
        or any(size == 0 for size in truth.shape[:2])
        or truth.shape[2:] != expected_tail
        or not np.all(np.isfinite(truth))
    ):
        raise ValueError(
            "truth forecasts must be finite [blocks, truths, origins, leads]"
        )
    forecast_values: dict[str, np.ndarray] = {}
    for method in _METHODS:
        values = np.asarray(forecasts[method], dtype=np.float64)
        if values.shape != truth.shape or not np.all(np.isfinite(values)):
            raise ValueError(f"{method} forecasts must be finite and match truth")
        forecast_values[method] = values
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

    squared_errors = {
        method: np.square(values - truth)
        for method, values in forecast_values.items()
    }
    rmse = {
        method: _masked_rmse(values, index.same_stage_mask)
        for method, values in squared_errors.items()
    }
    block_mse = {
        method: _block_mse(values, index.same_stage_mask)
        for method, values in squared_errors.items()
    }
    generator = np.random.default_rng(int(bootstrap_seed))
    bootstrap_indices = generator.integers(
        0,
        truth.shape[0],
        size=(int(bootstrap_replicates), truth.shape[0]),
        endpoint=False,
    )
    paired = {
        "full_minus_none": _paired_summary(
            block_mse["full"],
            block_mse["none"],
            bootstrap_indices,
            fraction,
        ),
        "full_minus_uniform_independent": _paired_summary(
            block_mse["full"],
            block_mse["uniform_independent"],
            bootstrap_indices,
            fraction,
        ),
    }
    gates = {
        "full_materially_improves_none_all_seven_leads": bool(
            np.all(paired["full_minus_none"]["materially_improves"])
        ),
        (
            "full_materially_improves_uniform_independent_"
            "all_seven_leads"
        ): bool(
            np.all(
                paired["full_minus_uniform_independent"][
                    "materially_improves"
                ]
            )
        ),
    }
    gates["retain"] = bool(all(gates.values()))
    strata = {
        name: _stratified_rmse(
            squared_errors,
            index,
            minimum,
            maximum,
        )
        for name, minimum, maximum in _TIME_STRATA
    }
    cross_switch_rmse = {
        method: _masked_rmse(values, index.cross_switch_mask)
        for method, values in squared_errors.items()
    }
    return {
        "methods": _METHODS,
        "lead_days": index.lead_days.copy(),
        "same_stage_sample_count_per_block_truth": np.sum(
            index.same_stage_mask,
            axis=0,
        ),
        "cross_switch_sample_count_per_block_truth": np.sum(
            index.cross_switch_mask,
            axis=0,
        ),
        "unavailable_sample_count_per_block_truth": np.sum(
            index.unavailable_mask,
            axis=0,
        ),
        "squared_errors": squared_errors,
        "rmse": rmse,
        "block_mse": block_mse,
        "paired": paired,
        "bootstrap_indices": bootstrap_indices,
        "retention_gates": gates,
        "time_strata": strata,
        "daily_offset": _daily_offset_summary(squared_errors, index),
        "cross_switch_rmse": cross_switch_rmse,
    }
