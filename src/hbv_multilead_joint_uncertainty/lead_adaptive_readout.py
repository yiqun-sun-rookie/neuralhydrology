"""Forecast readout rules that leave assimilation and interaction unchanged."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np


_ALLOWED_RULES = frozenset({"uniform", "highest_posterior"})
_PROBABILITY_SUM_ATOL = 1e-12
_SUMMARY_METHODS = (
    "lead_adaptive",
    "full_posterior",
    "none_posterior",
    "uniform",
    "oracle",
)


@dataclass(frozen=True)
class LeadAdaptiveReadout:
    """Immutable output from a lead-specific candidate forecast combination."""

    lead_days: np.ndarray
    predictions: np.ndarray
    weights: np.ndarray
    selected_candidate_index: int


def _readonly(array: np.ndarray) -> np.ndarray:
    result = np.array(array, copy=True)
    result.setflags(write=False)
    return result


def lead_adaptive_posterior_readout(
    final_probabilities: Sequence[float] | np.ndarray,
    candidate_predictions: Sequence[Sequence[float]] | np.ndarray,
    lead_days: Sequence[int] | np.ndarray,
    rule_by_lead: Mapping[int, str],
) -> LeadAdaptiveReadout:
    """Combine candidate forecasts by a preregistered rule for each lead.

    The function only reads final assimilation probabilities and candidate
    forecasts. It neither advances probabilities nor mixes candidate states.
    """

    probabilities = np.asarray(final_probabilities, dtype=np.float64)
    forecasts = np.asarray(candidate_predictions, dtype=np.float64)
    leads = np.asarray(lead_days)

    if probabilities.ndim != 1:
        raise ValueError("final probabilities must be one-dimensional")
    if probabilities.size == 0:
        raise ValueError("at least one candidate is required")
    if forecasts.ndim != 2:
        raise ValueError("candidate predictions must be two-dimensional")
    if forecasts.shape[1] != probabilities.size:
        raise ValueError("candidate dimension does not match probabilities")
    if leads.ndim != 1 or leads.size != forecasts.shape[0]:
        raise ValueError("lead dimension does not match candidate predictions")
    if not np.issubdtype(leads.dtype, np.integer):
        raise ValueError("lead days must be integers")
    leads = leads.astype(np.int64, copy=False)
    if np.any(leads <= 0):
        raise ValueError("lead days must be positive")
    if np.unique(leads).size != leads.size:
        raise ValueError("lead days must be unique")
    if not np.all(np.isfinite(probabilities)):
        raise ValueError("final probabilities must be finite")
    if not np.all(np.isfinite(forecasts)):
        raise ValueError("candidate predictions must be finite")
    if np.any(probabilities < 0.0):
        raise ValueError("final probabilities must be nonnegative")

    probability_sum = float(np.sum(probabilities))
    if not np.isclose(
        probability_sum,
        1.0,
        rtol=0.0,
        atol=_PROBABILITY_SUM_ATOL,
    ):
        raise ValueError("final probabilities must sum to one")
    probabilities = probabilities / probability_sum

    missing = [int(lead) for lead in leads if int(lead) not in rule_by_lead]
    if missing:
        raise ValueError(f"missing rule for lead days: {missing}")
    rules = [rule_by_lead[int(lead)] for lead in leads]
    invalid_rules = [rule for rule in rules if rule not in _ALLOWED_RULES]
    if invalid_rules:
        raise ValueError(f"unsupported readout rule: {invalid_rules[0]!r}")

    selected_index = int(np.argmax(probabilities))
    weights = np.empty_like(forecasts)
    uniform_weight = 1.0 / probabilities.size
    for row, rule in enumerate(rules):
        if rule == "uniform":
            weights[row] = uniform_weight
        else:
            weights[row] = 0.0
            weights[row, selected_index] = 1.0

    predictions = np.sum(weights * forecasts, axis=1)
    return LeadAdaptiveReadout(
        lead_days=_readonly(leads),
        predictions=_readonly(predictions),
        weights=_readonly(weights),
        selected_candidate_index=selected_index,
    )


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
    new_squared_error: np.ndarray,
    baseline_squared_error: np.ndarray,
    bootstrap_indices: np.ndarray,
    minimum_meaningful_rmse_fraction: float,
) -> dict[str, np.ndarray]:
    difference = new_squared_error - baseline_squared_error
    block_mean = np.mean(difference, axis=1)
    mean, ci_low, ci_high = _bootstrap_interval(
        block_mean,
        bootstrap_indices,
    )
    baseline_mse = np.mean(baseline_squared_error, axis=(0, 1))
    improvement_multiplier = (
        (1.0 - minimum_meaningful_rmse_fraction) ** 2 - 1.0
    )
    harm_multiplier = (
        (1.0 + minimum_meaningful_rmse_fraction) ** 2 - 1.0
    )
    improvement_boundary = baseline_mse * improvement_multiplier
    harm_boundary = baseline_mse * harm_multiplier
    return {
        "squared_error_difference": difference,
        "block_mean": block_mean,
        "mean": mean,
        "ci_low": ci_low,
        "ci_high": ci_high,
        "baseline_mse": baseline_mse,
        "meaningful_improvement_boundary": improvement_boundary,
        "meaningful_harm_boundary": harm_boundary,
        "materially_improves": ci_high < improvement_boundary,
        "no_material_harm": ci_high <= harm_boundary,
    }


def summarize_lead_adaptive_readout(
    forecasts: Mapping[str, np.ndarray],
    truth_forecasts: np.ndarray,
    final_probabilities: np.ndarray,
    final_true_candidate_indices: np.ndarray,
    lead_days: Sequence[int] | np.ndarray,
    bootstrap_replicates: int,
    bootstrap_seed: int,
    minimum_meaningful_rmse_fraction: float,
) -> dict[str, object]:
    """Compute frozen paired statistics and the preregistered retention gates.

    Forecast arrays use ``[matched block, truth case, lead]``. Paired
    differences are always ``lead_adaptive - baseline``. Truth cases are
    averaged within each matched block before block bootstrap resampling.
    """

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

    forecast_arrays: dict[str, np.ndarray] = {}
    for method in _SUMMARY_METHODS:
        values = np.asarray(forecasts[method], dtype=np.float64)
        if values.shape != truth.shape:
            raise ValueError(
                f"forecast shape for {method!r} must match truth forecasts"
            )
        if not np.all(np.isfinite(values)):
            raise ValueError(f"forecast values for {method!r} must be finite")
        forecast_arrays[method] = values

    leads = np.asarray(lead_days)
    if leads.ndim != 1 or leads.size != truth.shape[2]:
        raise ValueError("lead days must match the forecast lead dimension")
    if not np.issubdtype(leads.dtype, np.integer):
        raise ValueError("lead days must be integers")
    leads = leads.astype(np.int64, copy=False)
    if np.any(leads <= 0):
        raise ValueError("lead days must be positive")
    if np.unique(leads).size != leads.size:
        raise ValueError("lead days must be unique")
    multiday_mask = np.isin(leads, (3, 7))
    if int(np.sum(multiday_mask)) != 2:
        raise ValueError("lead days must contain exactly 3 and 7 days")

    probabilities = np.asarray(final_probabilities, dtype=np.float64)
    expected_probability_prefix = truth.shape[:2]
    if (
        probabilities.ndim != 3
        or probabilities.shape[:2] != expected_probability_prefix
        or probabilities.shape[2] == 0
    ):
        raise ValueError(
            "final probability shape must be [blocks, truths, candidates]"
        )
    if not np.all(np.isfinite(probabilities)):
        raise ValueError("final probabilities must be finite")
    if np.any(probabilities < 0.0):
        raise ValueError("final probabilities must be nonnegative")
    if not np.allclose(
        np.sum(probabilities, axis=-1),
        1.0,
        rtol=0.0,
        atol=_PROBABILITY_SUM_ATOL,
    ):
        raise ValueError("final probabilities must sum to one")

    true_indices = np.asarray(final_true_candidate_indices)
    if true_indices.shape == (truth.shape[1],):
        true_indices = np.broadcast_to(true_indices, truth.shape[:2])
    if true_indices.shape != truth.shape[:2]:
        raise ValueError(
            "true candidate indices must match [blocks, truths]"
        )
    if not np.issubdtype(true_indices.dtype, np.integer):
        raise ValueError("true candidate indices must be integers")
    true_indices = true_indices.astype(np.int64, copy=False)
    if np.any(true_indices < 0) or np.any(
        true_indices >= probabilities.shape[2]
    ):
        raise ValueError("true candidate index is out of range")

    if (
        not isinstance(bootstrap_replicates, (int, np.integer))
        or bootstrap_replicates <= 0
    ):
        raise ValueError("bootstrap replicates must be a positive integer")
    if not isinstance(bootstrap_seed, (int, np.integer)):
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
        for method, values in forecast_arrays.items()
    }
    rmse = {
        method: np.sqrt(np.mean(values, axis=(0, 1)))
        for method, values in squared_errors.items()
    }
    paired_none = _paired_summary(
        squared_errors["lead_adaptive"],
        squared_errors["none_posterior"],
        bootstrap_indices,
        fraction,
    )
    paired_full = _paired_summary(
        squared_errors["lead_adaptive"],
        squared_errors["full_posterior"],
        bootstrap_indices,
        fraction,
    )

    none_mse = np.mean(
        squared_errors["none_posterior"],
        axis=(0, 1),
    )
    if np.any(none_mse[multiday_mask] <= 0.0):
        raise ValueError(
            "none-posterior multiday MSE must be positive for normalization"
        )
    normalized_multiday_difference = (
        squared_errors["lead_adaptive"][..., multiday_mask]
        - squared_errors["none_posterior"][..., multiday_mask]
    ) / none_mse[multiday_mask]
    composite_block_mean = np.mean(
        normalized_multiday_difference,
        axis=(1, 2),
    )
    composite_mean, composite_low, composite_high = _bootstrap_interval(
        composite_block_mean,
        bootstrap_indices,
    )
    composite = {
        "lead_mask": multiday_mask,
        "normalized_squared_error_difference": (
            normalized_multiday_difference
        ),
        "block_mean": composite_block_mean,
        "mean": float(composite_mean),
        "ci_low": float(composite_low),
        "ci_high": float(composite_high),
    }

    selected_indices = np.argmax(probabilities, axis=-1)
    selection_accuracy = float(np.mean(selected_indices == true_indices))
    gates = {
        "none_at_least_one_material_improvement": bool(
            np.any(paired_none["materially_improves"])
        ),
        "none_all_leads_no_material_harm": bool(
            np.all(paired_none["no_material_harm"])
        ),
        "multiday_composite_improves": bool(composite_high < 0.0),
        "highest_posterior_selection_accuracy": bool(
            selection_accuracy >= 0.95
        ),
        "full_at_least_one_material_improvement": bool(
            np.any(paired_full["materially_improves"])
        ),
        "full_all_leads_no_material_harm": bool(
            np.all(paired_full["no_material_harm"])
        ),
    }
    gates["retain"] = bool(all(gates.values()))

    return {
        "methods": _SUMMARY_METHODS,
        "lead_days": leads.copy(),
        "squared_errors": squared_errors,
        "rmse": rmse,
        "paired": {
            "lead_adaptive_minus_none_posterior": paired_none,
            "lead_adaptive_minus_full_posterior": paired_full,
        },
        "bootstrap_indices": bootstrap_indices,
        "multiday_normalized_mse_composite": composite,
        "selected_candidate_indices": selected_indices,
        "true_candidate_indices": true_indices.copy(),
        "selection_accuracy": selection_accuracy,
        "retention_gates": gates,
    }
