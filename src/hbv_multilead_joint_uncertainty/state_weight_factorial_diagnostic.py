"""Pure forecast compositors for the state-path by final-weight diagnostic."""

from __future__ import annotations

import copy
from collections.abc import Mapping, Sequence
from dataclasses import dataclass

import numpy as np

from .forecast import forecast_from_posterior
from .methods import MethodCandidate, build_method_bank


def _as_real_float_array(value: object, name: str) -> np.ndarray:
    """Convert a real-valued input while normalizing public validation errors."""
    try:
        untyped = np.asarray(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{name} must be convertible to a real float array") from error
    if np.iscomplexobj(untyped):
        raise ValueError(f"{name} must be real-valued")
    try:
        return np.asarray(value, dtype=np.float64)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{name} must be convertible to a real float array") from error


def combine_candidate_forecasts(
    candidate_forecasts: np.ndarray,
    final_probabilities: np.ndarray,
) -> np.ndarray:
    """Combine candidate forecasts using one fixed final probability vector."""
    forecasts = _as_real_float_array(candidate_forecasts, "candidate_forecasts")
    probabilities = _as_real_float_array(final_probabilities, "final_probabilities")
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
    full_forecasts = _as_real_float_array(
        full_candidate_forecasts,
        "full_candidate_forecasts",
    )
    none_forecasts = _as_real_float_array(
        none_candidate_forecasts,
        "none_candidate_forecasts",
    )
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


@dataclass(frozen=True)
class TerminalAssimilationForecast:
    """Terminal candidate posteriors and one frozen-probability forecast."""

    daily_probabilities: np.ndarray
    final_candidate_states: np.ndarray
    final_candidate_covariances: np.ndarray
    candidate_forecasts: np.ndarray
    combined_forecast: np.ndarray


def _validated_positive_integer(value: object, name: str) -> int:
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, (int, np.integer)):
        raise ValueError(f"{name} must be a positive integer")
    result = int(value)
    if result <= 0:
        raise ValueError(f"{name} must be a positive integer")
    return result


def _validated_lead_days(leads: Sequence[int]) -> tuple[int, ...]:
    try:
        values = tuple(leads)
    except TypeError as error:
        raise ValueError("leads must be a nonempty sequence of integers") from error
    if not values or any(
        isinstance(value, (bool, np.bool_))
        or not isinstance(value, (int, np.integer))
        for value in values
    ):
        raise ValueError("leads must be a nonempty sequence of integers")
    result = tuple(int(value) for value in values)
    if any(value <= 0 for value in result) or any(
        current <= previous for previous, current in zip(result, result[1:])
    ):
        raise ValueError("leads must be positive, unique, and strictly increasing")
    return result


def _validated_scalar(value: object, name: str) -> float:
    if isinstance(value, (bool, np.bool_)):
        raise ValueError(f"{name} must be a finite scalar")
    try:
        untyped = np.asarray(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{name} must be a finite scalar") from error
    if untyped.ndim != 0 or np.iscomplexobj(untyped):
        raise ValueError(f"{name} must be a finite scalar")
    try:
        result = float(untyped)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{name} must be a finite scalar") from error
    if not np.isfinite(result):
        raise ValueError(f"{name} must be a finite scalar")
    return result


def _validated_probability_vector(value: object, candidate_count: int) -> np.ndarray:
    probabilities = _as_real_float_array(value, "candidate probabilities").copy()
    if probabilities.shape != (candidate_count,):
        raise ValueError("candidate probabilities must contain one value per candidate")
    if not np.all(np.isfinite(probabilities)) or np.any(probabilities < 0.0):
        raise ValueError("candidate probabilities must be finite and non-negative")
    if abs(float(probabilities.sum()) - 1.0) > 1e-12:
        raise ValueError("candidate probabilities must sum to one within 1e-12")
    return probabilities


def _readonly_copy(value: np.ndarray) -> np.ndarray:
    result = np.asarray(value, dtype=np.float64).copy()
    result.setflags(write=False)
    return result


def assimilate_terminal_forecast(
    candidates: Sequence[MethodCandidate],
    initial_states: Mapping[str, np.ndarray],
    initial_covariance: np.ndarray,
    active_forcing: np.ndarray,
    observations: np.ndarray,
    assimilation_days: int,
    leads: Sequence[int],
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
    interaction_mode: str,
) -> TerminalAssimilationForecast:
    """Assimilate one path and capture every terminal candidate before forecasting."""
    if interaction_mode not in {"full", "none"}:
        raise ValueError("interaction_mode must be full or none")
    days = _validated_positive_integer(assimilation_days, "assimilation_days")
    lead_days = _validated_lead_days(leads)

    try:
        definitions = tuple(copy.deepcopy(tuple(candidates)))
    except TypeError as error:
        raise ValueError("candidates must be a nonempty sequence") from error
    if not definitions:
        raise ValueError("candidates must be a nonempty sequence")
    if any(not hasattr(candidate, "parameter_id") for candidate in definitions):
        raise ValueError("each candidate must define parameter_id")
    candidate_count = len(definitions)

    if not isinstance(initial_states, Mapping) or not initial_states:
        raise ValueError("initial_states must be a nonempty mapping")
    copied_states = {}
    for parameter_id, state in initial_states.items():
        state_array = _as_real_float_array(state, "initial state").copy()
        if state_array.shape != (15,) or not np.all(np.isfinite(state_array)):
            raise ValueError("every initial state must be a finite 15-vector")
        copied_states[parameter_id] = state_array
    missing = {
        candidate.parameter_id
        for candidate in definitions
        if candidate.parameter_id not in copied_states
    }
    if missing:
        raise ValueError("initial_states is missing at least one candidate parameter_id")

    covariance = _as_real_float_array(initial_covariance, "initial_covariance").copy()
    if covariance.shape != (15, 15) or not np.all(np.isfinite(covariance)):
        raise ValueError("initial_covariance must be a finite 15 by 15 matrix")
    if not np.allclose(covariance, covariance.T, rtol=0.0, atol=1e-12):
        raise ValueError("initial_covariance must be symmetric")

    forcing = _as_real_float_array(active_forcing, "active_forcing").copy()
    if forcing.ndim != 2 or forcing.shape[1] != 3 or not np.all(np.isfinite(forcing)):
        raise ValueError("active_forcing must be a finite array with shape (days, 3)")
    required_days = days + lead_days[-1]
    if len(forcing) < required_days:
        raise ValueError("active_forcing does not cover assimilation plus maximum lead")

    observed = _as_real_float_array(observations, "observations").copy()
    if observed.ndim != 1 or len(observed) < days:
        raise ValueError("observations must be a vector covering every assimilation day")
    if not np.all(np.isfinite(observed[:days])):
        raise ValueError("observations must be finite on every assimilation day")

    observation_std = _validated_scalar(
        observation_standard_deviation, "observation_standard_deviation"
    )
    if observation_std <= 0.0:
        raise ValueError("observation_standard_deviation must be positive")
    stay_probability = _validated_scalar(
        factor_transition_stay_probability,
        "factor_transition_stay_probability",
    )
    if stay_probability < 0.0 or stay_probability > 1.0:
        raise ValueError("factor_transition_stay_probability must be between zero and one")

    bank = build_method_bank(
        candidates=definitions,
        initial_states=copied_states,
        initial_covariance=covariance,
        observation_standard_deviation=observation_std,
        factor_transition_stay_probability=stay_probability,
        interaction_mode=interaction_mode,
    )
    filters = tuple(bank.estimator.filters)
    transitions = tuple(bank.transitions)
    if len(filters) != candidate_count or len(transitions) != candidate_count:
        raise ValueError("candidate bank components must match the candidate count")

    daily_probabilities = np.empty((days, candidate_count), dtype=np.float64)
    for day in range(days):
        rain, potential_evaporation, temperature = forcing[day]
        for transition in transitions:
            transition.set_forcing(rain, potential_evaporation, temperature)
        bank.estimator.step(observed[day])
        daily_probabilities[day] = _validated_probability_vector(
            bank.estimator.probabilities, candidate_count
        )

    terminal_states = np.empty((candidate_count, 15), dtype=np.float64)
    terminal_covariances = np.empty((candidate_count, 15, 15), dtype=np.float64)
    for candidate_index, candidate_filter in enumerate(filters):
        state = _as_real_float_array(candidate_filter.state, "terminal candidate state")
        covariance_at_terminal = _as_real_float_array(
            candidate_filter.covariance, "terminal candidate covariance"
        )
        if state.shape != (15,) or not np.all(np.isfinite(state)):
            raise ValueError("every terminal candidate state must be a finite 15-vector")
        if covariance_at_terminal.shape != (15, 15) or not np.all(
            np.isfinite(covariance_at_terminal)
        ):
            raise ValueError(
                "every terminal candidate covariance must be a finite 15 by 15 matrix"
            )
        terminal_states[candidate_index] = state.copy()
        terminal_covariances[candidate_index] = covariance_at_terminal.copy()

    future = forcing[days:required_days].copy()
    forecast = forecast_from_posterior(
        bank,
        future,
        lead_days=lead_days,
        interaction_mode=interaction_mode,
    )
    forecast_probabilities = _as_real_float_array(
        forecast.probabilities, "forecast probabilities"
    ).copy()
    candidate_forecasts = _as_real_float_array(
        forecast.candidate_predictions, "candidate forecasts"
    ).copy()
    combined_forecast = _as_real_float_array(
        forecast.combined_predictions, "combined forecast"
    ).copy()
    lead_count = len(lead_days)
    if forecast_probabilities.shape != (lead_count, candidate_count):
        raise ValueError("forecast probabilities have an invalid shape")
    if candidate_forecasts.shape != (lead_count, candidate_count):
        raise ValueError("candidate forecasts have an invalid shape")
    if combined_forecast.shape != (lead_count,):
        raise ValueError("combined forecast has an invalid shape")
    if not all(
        np.all(np.isfinite(values))
        for values in (forecast_probabilities, candidate_forecasts, combined_forecast)
    ):
        raise ValueError("forecast outputs must be finite")

    frozen_probabilities = np.broadcast_to(
        daily_probabilities[-1], forecast_probabilities.shape
    )
    if not np.array_equal(forecast_probabilities, frozen_probabilities):
        raise RuntimeError("forecast probabilities must equal the final posterior")
    expected_combined = candidate_forecasts @ daily_probabilities[-1]
    maximum_combination_error = float(
        np.max(np.abs(combined_forecast - expected_combined))
    )
    if maximum_combination_error > 1e-12:
        raise RuntimeError(
            "combined forecast must use the final posterior probabilities; "
            f"maximum absolute error={maximum_combination_error}"
        )

    return TerminalAssimilationForecast(
        daily_probabilities=_readonly_copy(daily_probabilities),
        final_candidate_states=_readonly_copy(terminal_states),
        final_candidate_covariances=_readonly_copy(terminal_covariances),
        candidate_forecasts=_readonly_copy(candidate_forecasts),
        combined_forecast=_readonly_copy(combined_forecast),
    )
