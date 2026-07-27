"""Candidate-specific residual correction for multiday forecast readout."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

import numpy as np

from .predictive_skill_readout import (
    _readonly,
    rolling_predictive_skill_readout,
)


@dataclass(frozen=True)
class CandidateBiasCorrectedReadout:
    """Immutable posterior-weighted forecasts after rolling residual correction."""

    lead_days: np.ndarray
    predictions: np.ndarray
    weights: np.ndarray
    corrections: np.ndarray
    corrected_candidate_predictions: np.ndarray
    history_origin_indices: np.ndarray


def rolling_candidate_bias_corrected_readout(
    origin_indices: Sequence[int] | np.ndarray,
    target_indices: Sequence[Sequence[int]] | np.ndarray,
    historical_candidate_predictions: np.ndarray,
    observations: Sequence[float] | np.ndarray,
    final_candidate_predictions: np.ndarray,
    final_probabilities: Sequence[float] | np.ndarray,
    final_origin_index: int,
    lead_days: Sequence[int] | np.ndarray = (1, 3, 7),
    *,
    window: int = 30,
) -> CandidateBiasCorrectedReadout:
    """Correct three- and seven-day candidates by completed mean residuals.

    The one-day candidates are unchanged. At each longer lead, every candidate
    receives its own additive correction equal to the mean observed-minus-
    forecast residual over the latest completed same-lead window. Final
    posterior probabilities are then used unchanged for all leads.
    """

    validated = rolling_predictive_skill_readout(
        origin_indices=origin_indices,
        target_indices=target_indices,
        historical_candidate_predictions=historical_candidate_predictions,
        observations=observations,
        final_candidate_predictions=final_candidate_predictions,
        final_probabilities=final_probabilities,
        final_origin_index=final_origin_index,
        lead_days=lead_days,
        window=window,
    )
    origins = np.asarray(origin_indices, dtype=np.int64)
    targets = np.asarray(target_indices, dtype=np.int64)
    history = np.asarray(
        historical_candidate_predictions,
        dtype=np.float64,
    )
    observed = np.asarray(observations, dtype=np.float64)
    final_candidates = np.asarray(
        final_candidate_predictions,
        dtype=np.float64,
    )

    corrections = np.zeros_like(final_candidates)
    for lead_index in range(1, len(validated.lead_days)):
        used_origins = validated.history_origin_indices[lead_index]
        rows = np.searchsorted(origins, used_origins)
        if (
            np.any(rows >= len(origins))
            or not np.array_equal(origins[rows], used_origins)
        ):
            raise ValueError("history origin indices are missing")
        target_values = observed[targets[rows, lead_index]]
        corrections[lead_index] = np.mean(
            target_values[:, None] - history[rows, lead_index, :],
            axis=0,
        )

    corrected = final_candidates + corrections
    weights = np.broadcast_to(
        validated.weights[0],
        corrected.shape,
    ).copy()
    predictions = np.sum(weights * corrected, axis=1)
    return CandidateBiasCorrectedReadout(
        lead_days=_readonly(validated.lead_days),
        predictions=_readonly(predictions),
        weights=_readonly(weights),
        corrections=_readonly(corrections),
        corrected_candidate_predictions=_readonly(corrected),
        history_origin_indices=_readonly(
            validated.history_origin_indices
        ),
    )
