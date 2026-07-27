"""Forecast collection at fixed origins around parameter switches."""

from __future__ import annotations

import copy
from dataclasses import dataclass
from typing import Sequence

import numpy as np

from hbv_joint_uncertainty.preflight import CandidateBank

from .forecast import forecast_from_posterior


def _readonly(values) -> np.ndarray:
    result = np.array(values, copy=True)
    result.setflags(write=False)
    return result


def _validated_integer_vector(
    values: Sequence[int] | np.ndarray,
    name: str,
    *,
    allow_zero: bool,
) -> np.ndarray:
    array = np.asarray(values)
    if array.ndim != 1 or not np.issubdtype(array.dtype, np.integer):
        raise ValueError(f"{name} must be a one-dimensional integer array")
    array = array.astype(np.int64, copy=False)
    if len(array) == 0:
        raise ValueError(f"{name} must be nonempty")
    if allow_zero:
        if np.any(array < 0):
            raise ValueError(f"{name} must be nonnegative")
    elif np.any(array <= 0):
        raise ValueError(f"{name} must be positive")
    if np.any(np.diff(array) <= 0):
        raise ValueError(f"{name} must be strictly increasing")
    return array


def post_switch_origins(
    switch_days: Sequence[int] | np.ndarray,
    offsets: Sequence[int] | np.ndarray,
    *,
    crosscheck_origin: int | None = None,
) -> np.ndarray:
    """Return sorted switch-plus-offset origins and an optional cross-check."""

    switches = _validated_integer_vector(
        switch_days,
        "switch days",
        allow_zero=False,
    )
    offset_values = _validated_integer_vector(
        offsets,
        "offsets",
        allow_zero=True,
    )
    origins = {
        int(switch + offset)
        for switch in switches
        for offset in offset_values
    }
    if crosscheck_origin is not None:
        if (
            isinstance(crosscheck_origin, bool)
            or not isinstance(crosscheck_origin, (int, np.integer))
            or int(crosscheck_origin) < 0
        ):
            raise ValueError("crosscheck origin must be a nonnegative integer")
        origins.add(int(crosscheck_origin))
    return _readonly(np.asarray(sorted(origins), dtype=np.int64))


@dataclass(frozen=True)
class OriginForecasts:
    """Immutable forecasts and probabilities at explicitly requested origins."""

    lead_days: np.ndarray
    origin_indices: np.ndarray
    target_indices: np.ndarray
    predictions: np.ndarray
    candidate_predictions: np.ndarray
    probabilities: np.ndarray


def collect_forecasts_at_origins(
    forcing: np.ndarray,
    observations: Sequence[float] | np.ndarray,
    bank: CandidateBank,
    origin_indices: Sequence[int] | np.ndarray,
    lead_days: Sequence[int] | np.ndarray = (1, 3, 7),
    *,
    interaction_mode: str | None = None,
) -> OriginForecasts:
    """Assimilate once and forecast only at the requested causal origins."""

    origins = _validated_integer_vector(
        origin_indices,
        "origin indices",
        allow_zero=True,
    )
    leads = _validated_integer_vector(
        lead_days,
        "lead days",
        allow_zero=False,
    )
    forcing_values = np.asarray(forcing, dtype=np.float64)
    observed = np.asarray(observations, dtype=np.float64)
    required_days = int(origins[-1] + leads[-1] + 1)
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
        or len(observed) <= origins[-1]
        or not np.all(np.isfinite(observed[: origins[-1] + 1]))
    ):
        raise ValueError(
            "observations must be finite through the final requested origin"
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
    predictions = np.empty((len(origins), len(leads)), dtype=np.float64)
    candidate_predictions = np.empty(
        (len(origins), len(leads), candidate_count),
        dtype=np.float64,
    )
    probabilities = np.empty_like(candidate_predictions)
    origin_to_row = {
        int(origin): row for row, origin in enumerate(origins)
    }
    for day in range(int(origins[-1]) + 1):
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
            predictions[row] = forecast.combined_predictions
            candidate_predictions[row] = forecast.candidate_predictions
            probabilities[row] = forecast.probabilities

    if not all(
        np.all(np.isfinite(values))
        for values in (predictions, candidate_predictions, probabilities)
    ):
        raise ValueError("origin forecasts contain non-finite values")
    targets = origins[:, None] + leads[None, :]
    return OriginForecasts(
        lead_days=_readonly(leads),
        origin_indices=_readonly(origins),
        target_indices=_readonly(targets),
        predictions=_readonly(predictions),
        candidate_predictions=_readonly(candidate_predictions),
        probabilities=_readonly(probabilities),
    )
