"""Independent deterministic truth generation for closed HBV-lite experiments."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping

import numpy as np

from scl_hydro.hbv_lite_numpy import _half_triangular_lag, simulate_hbv_lite


HYDROLOGIC_STATE_NAMES = ("SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ")
PARAMETER_NAMES = (
    "parTT",
    "parCFMAX",
    "parCFR",
    "parCWH",
    "parFC",
    "parBETA",
    "parLP",
    "parK0",
    "parK1",
    "parUZL",
    "parPERC",
    "parK2",
    "lag_time",
)


@dataclass(frozen=True)
class ReferenceTruth:
    forcing: np.ndarray
    states: np.ndarray
    discharge: np.ndarray
    raw_discharge: np.ndarray


def _validated_forcing(forcing) -> np.ndarray:
    values = np.asarray(forcing, dtype=np.float64)
    if values.ndim != 2 or values.shape[1] != 3 or len(values) == 0:
        raise ValueError("forcing must have shape (days, 3) with at least one day")
    if not np.all(np.isfinite(values)):
        raise ValueError("forcing must contain only finite values")
    return values


def _validated_parameters(parameters: Mapping[str, float]) -> dict[str, float]:
    if set(parameters) != set(PARAMETER_NAMES):
        raise ValueError("parameters must contain exactly the thirteen HBV-lite parameters")
    values = {name: float(parameters[name]) for name in PARAMETER_NAMES}
    if not np.all(np.isfinite(list(values.values()))):
        raise ValueError("parameters must contain only finite values")
    return values


def _validated_state(state) -> np.ndarray:
    values = np.asarray(state, dtype=np.float64)
    if values.shape != (15,) or not np.all(np.isfinite(values)):
        raise ValueError("reference state must be one finite fifteen-element vector")
    return values


def project_reference_state(state, parameters: Mapping[str, float]) -> np.ndarray:
    """Project a reference state without calling the candidate-filter adapter."""
    values = _validated_state(state).copy()
    parameter_values = _validated_parameters(parameters)
    snow = max(float(values[0]), 0.0)
    values[0] = snow
    values[1] = np.clip(
        values[1],
        0.0,
        parameter_values["parCWH"] * snow,
    )
    values[2] = np.clip(values[2], 1e-5, parameter_values["parFC"])
    values[3:] = np.maximum(values[3:], 0.0)
    return values


def advance_reference_state(
    state,
    rain: float,
    potential_evaporation: float,
    temperature: float,
    parameters: Mapping[str, float],
) -> np.ndarray:
    """Advance one day through the authoritative simulator and shift saved runoff."""
    current = project_reference_state(state, parameters)
    parameter_values = _validated_parameters(parameters)
    forcing = np.asarray([rain, potential_evaporation, temperature], dtype=np.float64)
    if not np.all(np.isfinite(forcing)):
        raise ValueError("reference forcing must be finite")
    initial_stores = {
        name: float(value)
        for name, value in zip(HYDROLOGIC_STATE_NAMES, current[:5])
    }
    no_lag_parameters = {**parameter_values, "lag_time": 1.0}
    raw_discharge, final_stores = simulate_hbv_lite(
        np.asarray([forcing[0]], dtype=np.float64),
        np.asarray([forcing[1]], dtype=np.float64),
        np.asarray([forcing[2]], dtype=np.float64),
        no_lag_parameters,
        initial_state=initial_stores,
    )
    hydrologic = np.asarray(
        [final_stores[name] for name in HYDROLOGIC_STATE_NAMES], dtype=np.float64
    )
    routing_memory = np.concatenate(
        (np.asarray([raw_discharge[0]], dtype=np.float64), current[5:14])
    )
    return project_reference_state(
        np.concatenate((hydrologic, routing_memory)), parameter_values
    )


def reference_routed_discharge(state, lag_time: float) -> float:
    """Observe newest-first runoff memory without candidate-filter observation code."""
    values = _validated_state(state)
    lag = float(lag_time)
    if not np.isfinite(lag) or lag < 1.0 or lag > 10.0:
        raise ValueError("reference lag_time must be within one and ten days")
    count = int(np.ceil(lag))
    weights = np.arange(count, 0, -1, dtype=np.float64)
    weights /= weights.sum()
    return float(weights @ values[5:5 + count])


def generate_reference_truth(
    forcing,
    parameters: Mapping[str, float],
    initial_stores: Mapping[str, float] | None = None,
) -> ReferenceTruth:
    """Generate fifteen-state truth through the separate authoritative HBV-lite path."""
    forcing_values = _validated_forcing(forcing)
    parameter_values = _validated_parameters(parameters)
    stores = {
        "SNOWPACK": 0.0,
        "MELTWATER": 0.0,
        "SM": parameter_values["parFC"] * 0.3,
        "SUZ": 5.0,
        "SLZ": 10.0,
    }
    if initial_stores is not None:
        if set(initial_stores) != set(HYDROLOGIC_STATE_NAMES):
            raise ValueError("initial_stores must contain exactly the five hydrologic states")
        stores = {name: float(initial_stores[name]) for name in HYDROLOGIC_STATE_NAMES}
        if not np.all(np.isfinite(list(stores.values()))):
            raise ValueError("initial_stores must contain only finite values")

    day_count = len(forcing_values)
    hydrologic_states = np.empty((day_count, 5), dtype=np.float64)
    raw_discharge = np.empty(day_count, dtype=np.float64)
    no_lag_parameters = {**parameter_values, "lag_time": 1.0}
    for day, (rain, potential_evaporation, temperature) in enumerate(forcing_values):
        daily_discharge, stores = simulate_hbv_lite(
            np.asarray([rain], dtype=np.float64),
            np.asarray([potential_evaporation], dtype=np.float64),
            np.asarray([temperature], dtype=np.float64),
            no_lag_parameters,
            initial_state=stores,
        )
        raw_discharge[day] = daily_discharge[0]
        hydrologic_states[day] = [stores[name] for name in HYDROLOGIC_STATE_NAMES]

    routing_memory = np.zeros((day_count, 10), dtype=np.float64)
    for day in range(day_count):
        history = raw_discharge[max(0, day - 9):day + 1][::-1]
        routing_memory[day, :len(history)] = history
    states = np.column_stack((hydrologic_states, routing_memory))
    discharge = _half_triangular_lag(raw_discharge, parameter_values["lag_time"])
    return ReferenceTruth(
        forcing=forcing_values.copy(),
        states=states,
        discharge=np.asarray(discharge, dtype=np.float64),
        raw_discharge=raw_discharge,
    )
