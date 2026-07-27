"""Forecast readout based only on already verified candidate skill."""

from __future__ import annotations

import copy
from dataclasses import dataclass
from typing import Sequence

import numpy as np

from hbv_joint_uncertainty.preflight import CandidateBank

from .forecast import forecast_from_posterior


_REQUIRED_LEADS = (1, 3, 7)
_PROBABILITY_ATOL = 1e-12


def _readonly(value) -> np.ndarray:
    result = np.array(value, copy=True)
    result.setflags(write=False)
    return result


def _validated_window(window: int) -> int:
    if (
        isinstance(window, bool)
        or not isinstance(window, (int, np.integer))
        or int(window) <= 0
    ):
        raise ValueError("window must be a positive integer")
    return int(window)


def _validated_leads(lead_days: Sequence[int] | np.ndarray) -> np.ndarray:
    leads = np.asarray(lead_days)
    if (
        leads.ndim != 1
        or not np.issubdtype(leads.dtype, np.integer)
        or tuple(int(value) for value in leads) != _REQUIRED_LEADS
    ):
        raise ValueError("lead days must be exactly 1, 3, and 7")
    return leads.astype(np.int64, copy=False)


def _validated_final_origin(final_origin_index: int) -> int:
    if (
        isinstance(final_origin_index, bool)
        or not isinstance(final_origin_index, (int, np.integer))
        or int(final_origin_index) < 0
    ):
        raise ValueError("final origin index must be a nonnegative integer")
    return int(final_origin_index)


def required_hindcast_origins(
    final_origin_index: int,
    lead_days: Sequence[int] | np.ndarray = _REQUIRED_LEADS,
    *,
    window: int = 30,
) -> np.ndarray:
    """Return the minimal origin set needed for long-lead scoring and output."""

    final_origin = _validated_final_origin(final_origin_index)
    leads = _validated_leads(lead_days)
    count = _validated_window(window)
    required = {final_origin}
    for lead in leads[1:]:
        last = final_origin - int(lead)
        first = last - count + 1
        if first < 0:
            raise ValueError(
                "insufficient completed forecasts for the requested window"
            )
        required.update(range(first, last + 1))
    return _readonly(np.asarray(sorted(required), dtype=np.int64))


@dataclass(frozen=True)
class PredictiveSkillReadout:
    """Immutable one-, three-, and seven-day skill-based forecast readout."""

    lead_days: np.ndarray
    predictions: np.ndarray
    weights: np.ndarray
    historical_mean_squared_errors: np.ndarray
    selected_candidate_indices: np.ndarray
    history_origin_indices: np.ndarray


@dataclass(frozen=True)
class RecentCandidateHindcasts:
    """Minimal immutable candidate hindcasts needed by the skill readout."""

    lead_days: np.ndarray
    origin_indices: np.ndarray
    target_indices: np.ndarray
    candidate_predictions: np.ndarray
    final_probabilities: np.ndarray


def collect_recent_candidate_hindcasts(
    forcing: np.ndarray,
    observations: Sequence[float] | np.ndarray,
    bank: CandidateBank,
    final_origin_index: int,
    lead_days: Sequence[int] | np.ndarray = _REQUIRED_LEADS,
    *,
    window: int = 30,
    interaction_mode: str | None = None,
) -> RecentCandidateHindcasts:
    """Assimilate once and forecast only at origins required for scoring."""

    leads = _validated_leads(lead_days)
    count = _validated_window(window)
    final_origin = _validated_final_origin(final_origin_index)
    required = required_hindcast_origins(
        final_origin,
        leads,
        window=count,
    )
    forcing_values = np.asarray(forcing, dtype=np.float64)
    observed = np.asarray(observations, dtype=np.float64)
    required_days = final_origin + int(leads[-1]) + 1
    if (
        forcing_values.ndim != 2
        or forcing_values.shape[1] != 3
        or len(forcing_values) < required_days
        or not np.all(np.isfinite(forcing_values[:required_days]))
    ):
        raise ValueError(
            "forcing must be finite, have three columns, and cover all forecasts"
        )
    if (
        observed.ndim != 1
        or len(observed) <= final_origin
        or not np.all(np.isfinite(observed[: final_origin + 1]))
    ):
        raise ValueError(
            "observations must be finite through the final origin"
        )

    branch = copy.deepcopy(bank)
    mode = interaction_mode or getattr(
        branch.estimator,
        "interaction_mode",
        "full",
    )
    if mode not in {"full", "parameter_grouped", "none"}:
        raise ValueError("interaction mode is invalid")
    branch.estimator.interaction_mode = mode
    candidate_count = len(branch.estimator.filters)
    predictions = np.empty(
        (len(required), len(leads), candidate_count),
        dtype=np.float64,
    )
    origin_to_row = {
        int(origin): row for row, origin in enumerate(required)
    }
    for day in range(final_origin + 1):
        rain, potential_evaporation, temperature = forcing_values[day]
        for transition in branch.transitions:
            transition.set_forcing(
                rain,
                potential_evaporation,
                temperature,
            )
        branch.estimator.step(observed[day])
        row = origin_to_row.get(day)
        if row is not None:
            future = forcing_values[
                day + 1 : day + int(leads[-1]) + 1
            ]
            forecast = forecast_from_posterior(
                branch,
                future,
                lead_days=leads,
                interaction_mode=mode,
            )
            predictions[row] = forecast.candidate_predictions

    if not np.all(np.isfinite(predictions)):
        raise ValueError("candidate hindcasts contain non-finite values")
    targets = required[:, None] + leads[None, :]
    return RecentCandidateHindcasts(
        lead_days=_readonly(leads),
        origin_indices=_readonly(required),
        target_indices=_readonly(targets),
        candidate_predictions=_readonly(predictions),
        final_probabilities=_readonly(branch.estimator.probabilities),
    )


def rolling_predictive_skill_readout(
    origin_indices: Sequence[int] | np.ndarray,
    target_indices: Sequence[Sequence[int]] | np.ndarray,
    historical_candidate_predictions: np.ndarray,
    observations: Sequence[float] | np.ndarray,
    final_candidate_predictions: np.ndarray,
    final_probabilities: Sequence[float] | np.ndarray,
    final_origin_index: int,
    lead_days: Sequence[int] | np.ndarray = _REQUIRED_LEADS,
    *,
    window: int = 30,
) -> PredictiveSkillReadout:
    """Select long-lead candidates by their latest completed forecast errors."""

    leads = _validated_leads(lead_days)
    count = _validated_window(window)
    final_origin = _validated_final_origin(final_origin_index)
    origins = np.asarray(origin_indices)
    targets = np.asarray(target_indices)
    history = np.asarray(
        historical_candidate_predictions,
        dtype=np.float64,
    )
    observed = np.asarray(observations, dtype=np.float64)
    final_candidates = np.asarray(
        final_candidate_predictions,
        dtype=np.float64,
    )
    probabilities = np.asarray(final_probabilities, dtype=np.float64)

    if origins.ndim != 1 or not np.issubdtype(origins.dtype, np.integer):
        raise ValueError("origin indices must be a one-dimensional integer array")
    origins = origins.astype(np.int64, copy=False)
    if len(origins) == 0 or np.any(np.diff(origins) <= 0):
        raise ValueError("origin indices must be nonempty and strictly increasing")
    if targets.shape != (len(origins), len(leads)):
        raise ValueError("target indices must match origins and lead days")
    if not np.issubdtype(targets.dtype, np.integer):
        raise ValueError("target indices must be integers")
    targets = targets.astype(np.int64, copy=False)
    expected_targets = origins[:, None] + leads[None, :]
    if not np.array_equal(targets, expected_targets):
        raise ValueError("target indices must equal origin plus lead")
    if history.ndim != 3 or history.shape[:2] != targets.shape:
        raise ValueError(
            "historical candidate predictions must match origins and leads"
        )
    candidate_count = history.shape[2]
    if candidate_count == 0:
        raise ValueError("at least one candidate is required")
    if final_candidates.shape != (len(leads), candidate_count):
        raise ValueError(
            "final candidate predictions must match leads and candidates"
        )
    if probabilities.shape != (candidate_count,):
        raise ValueError("final probabilities must match candidates")
    if observed.ndim != 1 or len(observed) <= final_origin:
        raise ValueError("observations must cover the final origin")
    if not np.all(np.isfinite(observed[: final_origin + 1])):
        raise ValueError("completed observations must be finite")
    if not np.all(np.isfinite(history)) or not np.all(
        np.isfinite(final_candidates)
    ):
        raise ValueError("candidate predictions must be finite")
    if (
        not np.all(np.isfinite(probabilities))
        or np.any(probabilities < 0.0)
        or not np.isclose(
            np.sum(probabilities),
            1.0,
            rtol=0.0,
            atol=_PROBABILITY_ATOL,
        )
    ):
        raise ValueError(
            "final probabilities must be finite, nonnegative, and sum to one"
        )

    normalized_probabilities = probabilities / np.sum(probabilities)
    weights = np.zeros_like(final_candidates)
    weights[0] = normalized_probabilities
    scores = np.full_like(final_candidates, np.nan)
    selected = np.full(len(leads), -1, dtype=np.int64)
    used_origins = np.full((len(leads), count), -1, dtype=np.int64)
    for lead_index in range(1, len(leads)):
        eligible = np.flatnonzero(
            targets[:, lead_index] <= final_origin
        )
        if len(eligible) < count:
            raise ValueError(
                "insufficient completed forecasts for the requested window"
            )
        rows = eligible[-count:]
        used_origins[lead_index] = origins[rows]
        target_values = observed[targets[rows, lead_index]]
        residuals = (
            history[rows, lead_index, :]
            - target_values[:, None]
        )
        scores[lead_index] = np.mean(np.square(residuals), axis=0)
        candidate_index = int(np.argmin(scores[lead_index]))
        selected[lead_index] = candidate_index
        weights[lead_index, candidate_index] = 1.0

    predictions = np.sum(weights * final_candidates, axis=1)
    return PredictiveSkillReadout(
        lead_days=_readonly(leads),
        predictions=_readonly(predictions),
        weights=_readonly(weights),
        historical_mean_squared_errors=_readonly(scores),
        selected_candidate_indices=_readonly(selected),
        history_origin_indices=_readonly(used_origins),
    )
