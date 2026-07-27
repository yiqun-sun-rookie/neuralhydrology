"""Forecast readout rules that leave assimilation and interaction unchanged."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np


_ALLOWED_RULES = frozenset({"uniform", "highest_posterior"})
_PROBABILITY_SUM_ATOL = 1e-12


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
