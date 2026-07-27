"""Time-robust posterior readout without changing assimilation or interaction."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np

from .lead_adaptive_readout import _paired_summary


_PROBABILITY_SUM_ATOL = 1e-12
_REQUIRED_LEADS = (1, 3, 7)
_SUMMARY_METHODS = (
    "temporal_posterior",
    "full_posterior",
    "none_posterior",
)


def _readonly(value: np.ndarray) -> np.ndarray:
    result = np.array(value, copy=True)
    result.setflags(write=False)
    return result


@dataclass(frozen=True)
class TemporalPosteriorReadout:
    """Immutable one-, three-, and seven-day temporal readout."""

    lead_days: np.ndarray
    predictions: np.ndarray
    weights: np.ndarray
    temporal_mean_probabilities: np.ndarray
    selected_candidate_index: int


def temporal_posterior_readout(
    probability_history: Sequence[Sequence[float]] | np.ndarray,
    candidate_predictions: Sequence[Sequence[float]] | np.ndarray,
    lead_days: Sequence[int] | np.ndarray = _REQUIRED_LEADS,
    *,
    window_days: int = 30,
) -> TemporalPosteriorReadout:
    """Keep the one-day posterior mean and time-robustly select longer leads."""

    if (
        isinstance(window_days, bool)
        or not isinstance(window_days, (int, np.integer))
        or int(window_days) <= 0
    ):
        raise ValueError("window days must be a positive integer")
    window = int(window_days)
    history = np.asarray(probability_history, dtype=np.float64)
    forecasts = np.asarray(candidate_predictions, dtype=np.float64)
    leads = np.asarray(lead_days)

    if history.ndim != 2:
        raise ValueError("probability history must be two-dimensional")
    if len(history) < window:
        raise ValueError(
            "probability history must contain at least window_days rows"
        )
    if history.shape[1] == 0:
        raise ValueError("at least one candidate is required")
    if forecasts.ndim != 2:
        raise ValueError("candidate predictions must be two-dimensional")
    if forecasts.shape[1] != history.shape[1]:
        raise ValueError(
            "candidate dimension must match probability history"
        )
    if leads.ndim != 1 or len(leads) != forecasts.shape[0]:
        raise ValueError(
            "lead dimension must match candidate predictions"
        )
    if not np.issubdtype(leads.dtype, np.integer):
        raise ValueError("lead days must be integers")
    leads = leads.astype(np.int64, copy=False)
    if tuple(int(value) for value in leads) != _REQUIRED_LEADS:
        raise ValueError("lead days must be exactly 1, 3, and 7")
    if not np.all(np.isfinite(history)):
        raise ValueError("probability history must be finite")
    if np.any(history < 0.0):
        raise ValueError("probability history must be nonnegative")
    if not np.allclose(
        np.sum(history, axis=1),
        1.0,
        rtol=0.0,
        atol=_PROBABILITY_SUM_ATOL,
    ):
        raise ValueError("every probability row must sum to one")
    if not np.all(np.isfinite(forecasts)):
        raise ValueError("candidate predictions must be finite")

    normalized_history = history / np.sum(
        history,
        axis=1,
        keepdims=True,
    )
    final_probabilities = normalized_history[-1]
    temporal_probabilities = np.mean(
        normalized_history[-window:],
        axis=0,
    )
    temporal_probabilities /= np.sum(temporal_probabilities)
    selected_index = int(np.argmax(temporal_probabilities))

    weights = np.zeros_like(forecasts)
    weights[0] = final_probabilities
    weights[1:, selected_index] = 1.0
    predictions = np.sum(weights * forecasts, axis=1)
    return TemporalPosteriorReadout(
        lead_days=_readonly(leads),
        predictions=_readonly(predictions),
        weights=_readonly(weights),
        temporal_mean_probabilities=_readonly(temporal_probabilities),
        selected_candidate_index=selected_index,
    )


def summarize_temporal_posterior_readout(
    forecasts: Mapping[str, np.ndarray],
    truth_forecasts: np.ndarray,
    selected_candidate_indices: np.ndarray,
    true_candidate_indices: np.ndarray,
    lead_days: Sequence[int] | np.ndarray,
    bootstrap_replicates: int,
    bootstrap_seed: int,
    minimum_meaningful_rmse_fraction: float,
    minimum_selection_accuracy: float,
) -> dict[str, object]:
    """Compute matched-block intervals and the frozen retention decision."""

    if set(forecasts) != set(_SUMMARY_METHODS):
        raise ValueError(
            "forecasts must contain exactly the preregistered methods"
        )
    truth = np.asarray(truth_forecasts, dtype=np.float64)
    if truth.ndim != 3 or any(size == 0 for size in truth.shape):
        raise ValueError(
            "truth forecast shape must be [blocks, truths, leads]"
        )
    if not np.all(np.isfinite(truth)):
        raise ValueError("truth forecasts must be finite")

    arrays: dict[str, np.ndarray] = {}
    for method in _SUMMARY_METHODS:
        values = np.asarray(forecasts[method], dtype=np.float64)
        if values.shape != truth.shape:
            raise ValueError(
                f"forecast shape for {method!r} must match truth forecasts"
            )
        if not np.all(np.isfinite(values)):
            raise ValueError(
                f"forecast values for {method!r} must be finite"
            )
        arrays[method] = values.copy()

    leads = np.asarray(lead_days)
    if (
        leads.ndim != 1
        or not np.issubdtype(leads.dtype, np.integer)
        or tuple(int(value) for value in leads) != _REQUIRED_LEADS
        or truth.shape[2] != len(_REQUIRED_LEADS)
    ):
        raise ValueError("lead days must be exactly 1, 3, and 7")
    leads = leads.astype(np.int64, copy=False)

    selected = np.asarray(selected_candidate_indices)
    true = np.asarray(true_candidate_indices)
    if selected.shape != truth.shape[:2] or true.shape != truth.shape[:2]:
        raise ValueError(
            "candidate indices must match [blocks, truths]"
        )
    if not np.issubdtype(selected.dtype, np.integer) or not np.issubdtype(
        true.dtype,
        np.integer,
    ):
        raise ValueError("candidate indices must be integers")
    selected = selected.astype(np.int64, copy=False)
    true = true.astype(np.int64, copy=False)
    if np.any(selected < 0) or np.any(true < 0):
        raise ValueError("candidate indices must be nonnegative")

    if (
        isinstance(bootstrap_replicates, bool)
        or not isinstance(bootstrap_replicates, (int, np.integer))
        or int(bootstrap_replicates) <= 0
    ):
        raise ValueError(
            "bootstrap replicates must be a positive integer"
        )
    if isinstance(bootstrap_seed, bool) or not isinstance(
        bootstrap_seed,
        (int, np.integer),
    ):
        raise ValueError("bootstrap seed must be an integer")
    fraction = float(minimum_meaningful_rmse_fraction)
    if not np.isfinite(fraction) or not 0.0 < fraction < 1.0:
        raise ValueError(
            "minimum meaningful RMSE fraction must be between zero and one"
        )
    selection_minimum = float(minimum_selection_accuracy)
    if (
        not np.isfinite(selection_minimum)
        or not 0.0 < selection_minimum <= 1.0
    ):
        raise ValueError(
            "minimum selection accuracy must be in (0, 1]"
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
        for method, values in arrays.items()
    }
    rmse = {
        method: np.sqrt(np.mean(values, axis=(0, 1)))
        for method, values in squared_errors.items()
    }
    paired_full = _paired_summary(
        squared_errors["temporal_posterior"],
        squared_errors["full_posterior"],
        bootstrap_indices,
        fraction,
    )
    paired_none = _paired_summary(
        squared_errors["temporal_posterior"],
        squared_errors["none_posterior"],
        bootstrap_indices,
        fraction,
    )

    one_day_difference = float(
        np.max(
            np.abs(
                arrays["temporal_posterior"][..., 0]
                - arrays["full_posterior"][..., 0]
            ),
            initial=0.0,
        )
    )
    selection_accuracy = float(np.mean(selected == true))
    gates = {
        "one_day_exact": bool(one_day_difference <= 1e-12),
        "selection_accuracy": bool(
            selection_accuracy >= selection_minimum
        ),
        "three_day_no_material_harm_vs_full": bool(
            paired_full["ci_high"][1]
            < paired_full["meaningful_harm_boundary"][1]
        ),
        "seven_day_material_improvement_vs_full": bool(
            paired_full["ci_high"][2]
            < paired_full["meaningful_improvement_boundary"][2]
        ),
        "three_day_no_material_harm_vs_none": bool(
            paired_none["ci_high"][1]
            < paired_none["meaningful_harm_boundary"][1]
        ),
        "seven_day_material_improvement_vs_none": bool(
            paired_none["ci_high"][2]
            < paired_none["meaningful_improvement_boundary"][2]
        ),
    }
    gates["retain"] = bool(all(gates.values()))

    return {
        "methods": _SUMMARY_METHODS,
        "lead_days": leads.copy(),
        "forecasts": arrays,
        "squared_errors": squared_errors,
        "rmse": rmse,
        "paired": {
            "temporal_minus_full_posterior": paired_full,
            "temporal_minus_none_posterior": paired_none,
        },
        "bootstrap_indices": bootstrap_indices,
        "selected_candidate_indices": selected.copy(),
        "true_candidate_indices": true.copy(),
        "selection_accuracy": selection_accuracy,
        "one_day_maximum_absolute_difference": one_day_difference,
        "retention_gates": gates,
    }
