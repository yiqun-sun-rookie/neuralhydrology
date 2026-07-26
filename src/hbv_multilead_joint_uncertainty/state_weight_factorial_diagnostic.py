"""Pure forecast compositors for the state-path by final-weight diagnostic."""

from __future__ import annotations

import numpy as np


def combine_candidate_forecasts(
    candidate_forecasts: np.ndarray,
    final_probabilities: np.ndarray,
) -> np.ndarray:
    """Combine candidate forecasts using one fixed final probability vector."""
    forecasts = np.asarray(candidate_forecasts, dtype=np.float64)
    probabilities = np.asarray(final_probabilities, dtype=np.float64)
    if forecasts.ndim != 2 or not np.all(np.isfinite(forecasts)):
        raise ValueError("candidate_forecasts must be a finite (lead, candidate) array")
    if probabilities.ndim != 1 or probabilities.shape[0] != forecasts.shape[1]:
        raise ValueError("final_probabilities must contain one value per candidate")
    if not np.all(np.isfinite(probabilities)) or np.any(probabilities < 0.0):
        raise ValueError("final_probabilities must be finite and non-negative")
    if abs(float(probabilities.sum()) - 1.0) > 1e-12:
        raise ValueError("final_probabilities must sum to one within 1e-12")
    return forecasts @ probabilities


def state_weight_factorial_forecasts(
    full_candidate_forecasts: np.ndarray,
    none_candidate_forecasts: np.ndarray,
    full_final_probabilities: np.ndarray,
    none_final_probabilities: np.ndarray,
) -> dict[str, np.ndarray]:
    """Cross two candidate-forecast paths with two final probability vectors."""
    full_forecasts = np.asarray(full_candidate_forecasts, dtype=np.float64)
    none_forecasts = np.asarray(none_candidate_forecasts, dtype=np.float64)
    if full_forecasts.shape != none_forecasts.shape:
        raise ValueError("full and none candidate forecasts must have identical shapes")

    full_states_full_weights = combine_candidate_forecasts(
        full_forecasts,
        full_final_probabilities,
    )
    full_states_none_weights = combine_candidate_forecasts(
        full_forecasts,
        none_final_probabilities,
    )
    none_states_full_weights = combine_candidate_forecasts(
        none_forecasts,
        full_final_probabilities,
    )
    none_states_none_weights = combine_candidate_forecasts(
        none_forecasts,
        none_final_probabilities,
    )
    return {
        "full_states_full_weights": full_states_full_weights,
        "full_states_none_weights": full_states_none_weights,
        "none_states_full_weights": none_states_full_weights,
        "none_states_none_weights": none_states_none_weights,
        "prediction_nonadditivity": (
            full_states_full_weights
            - full_states_none_weights
            - none_states_full_weights
            + none_states_none_weights
        ),
    }
