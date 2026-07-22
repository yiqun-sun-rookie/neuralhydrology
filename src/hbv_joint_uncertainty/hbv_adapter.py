"""Exact-state helpers for the daily NumPy HBV-lite model."""

from __future__ import annotations

from typing import Sequence

import numpy as np


HYDRO_STATE_NAMES = ("SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ")
ROUTING_STATE_NAMES = tuple(f"qraw_t_minus_{offset}" for offset in range(10))
STATE_NAMES = HYDRO_STATE_NAMES + ROUTING_STATE_NAMES
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
V1_PARAMETER_BOUNDS = {
    "parTT": (-2.5, 2.5),
    "parCFMAX": (0.5, 10.0),
    "parCFR": (0.0, 0.1),
    "parCWH": (0.0, 0.2),
    "parFC": (50.0, 1000.0),
    "parBETA": (1.0, 6.0),
    "parLP": (0.2, 1.0),
    "parK0": (0.05, 0.9),
    "parK1": (0.01, 0.5),
    "parUZL": (0.0, 100.0),
    "parPERC": (0.0, 10.0),
    "parK2": (0.001, 0.2),
    "lag_time": (1.0, 10.0),
}


def _as_finite_vector(values: Sequence[float], expected_size: int, label: str) -> np.ndarray:
    vector = np.asarray(values, dtype=np.float64)
    if vector.shape != (expected_size,):
        raise ValueError(f"{label} must have shape ({expected_size},), got {vector.shape}")
    if not np.all(np.isfinite(vector)):
        raise ValueError(f"{label} must contain only finite values")
    return vector


def pack_state(hydrologic: Sequence[float], routing: Sequence[float]) -> np.ndarray:
    """Pack five stores and ten newest-first raw-runoff values."""
    stores = _as_finite_vector(hydrologic, len(HYDRO_STATE_NAMES), "hydrologic")
    memory = _as_finite_vector(routing, len(ROUTING_STATE_NAMES), "routing")
    return np.concatenate((stores, memory))


def _validated_parameters(params: dict) -> dict[str, float]:
    missing = [name for name in PARAMETER_NAMES if name not in params]
    if missing:
        raise ValueError(f"missing HBV-lite parameters: {missing}")
    values = {name: float(params[name]) for name in PARAMETER_NAMES}
    if not np.all(np.isfinite(list(values.values()))):
        raise ValueError("HBV-lite parameters must be finite")
    for name, (lower, upper) in V1_PARAMETER_BOUNDS.items():
        if values[name] < lower or values[name] > upper:
            raise ValueError(
                f"parameter {name}={values[name]!r} is outside explicit v1 bounds [{lower}, {upper}]"
            )
    return values


def initial_state_vector(params: dict, initial_state: dict | None = None) -> np.ndarray:
    """Return the authoritative five-store default plus zero routing history."""
    values = _validated_parameters(params)
    supplied = initial_state or {}
    stores = np.array(
        [
            float(supplied.get("SNOWPACK", 0.0)),
            float(supplied.get("MELTWATER", 0.0)),
            float(supplied.get("SM", values["parFC"] * 0.3)),
            float(supplied.get("SUZ", 5.0)),
            float(supplied.get("SLZ", 10.0)),
        ],
        dtype=np.float64,
    )
    return pack_state(stores, np.zeros(len(ROUTING_STATE_NAMES), dtype=np.float64))


def advance_state(state: Sequence[float], rain: float, pet: float, temp: float, params: dict) -> np.ndarray:
    """Advance the exact HBV-lite equations by one day and shift routing memory."""
    current = _as_finite_vector(state, len(STATE_NAMES), "state")
    p = _validated_parameters(params)
    forcing = np.asarray([rain, pet, temp], dtype=np.float64)
    if not np.all(np.isfinite(forcing)):
        raise ValueError("rain, pet, and temp must be finite")

    precipitation, potential_evaporation, temperature = (float(value) for value in forcing)
    snowpack, meltwater, soil, upper, lower = (float(value) for value in current[:5])
    eps = 1e-5

    if temperature < p["parTT"]:
        snowfall = precipitation
        rainfall = 0.0
    else:
        snowfall = 0.0
        rainfall = precipitation

    snowpack = snowpack + snowfall
    melt = p["parCFMAX"] * (temperature - p["parTT"])
    if melt < 0.0:
        melt = 0.0
    if melt > snowpack:
        melt = snowpack
    meltwater = meltwater + melt
    snowpack = snowpack - melt

    refreezing = p["parCFR"] * p["parCFMAX"] * (p["parTT"] - temperature)
    if refreezing < 0.0:
        refreezing = 0.0
    if refreezing > meltwater:
        refreezing = meltwater
    snowpack = snowpack + refreezing
    meltwater = meltwater - refreezing

    to_soil = meltwater - p["parCWH"] * snowpack
    if to_soil < 0.0:
        to_soil = 0.0
    meltwater = meltwater - to_soil

    ratio = soil / (p["parFC"] + eps)
    if ratio < 0.0:
        ratio = 0.0
    if ratio > 1.0:
        ratio = 1.0
    soil_wetness = ratio**p["parBETA"]
    if soil_wetness < 0.0:
        soil_wetness = 0.0
    if soil_wetness > 1.0:
        soil_wetness = 1.0
    recharge = (rainfall + to_soil) * soil_wetness
    soil = soil + rainfall + to_soil - recharge

    excess = soil - p["parFC"]
    if excess < 0.0:
        excess = 0.0
    soil = soil - excess

    evaporation_factor = soil / (p["parLP"] * p["parFC"] + eps)
    if evaporation_factor < 0.0:
        evaporation_factor = 0.0
    if evaporation_factor > 1.0:
        evaporation_factor = 1.0
    actual_evaporation = potential_evaporation * evaporation_factor
    if actual_evaporation > soil:
        actual_evaporation = soil
    soil = soil - actual_evaporation
    if soil < eps:
        soil = eps

    upper = upper + recharge + excess
    percolation = p["parPERC"]
    if percolation > upper:
        percolation = upper
    upper = upper - percolation
    upper_excess = upper - p["parUZL"]
    if upper_excess < 0.0:
        upper_excess = 0.0
    fast_runoff = p["parK0"] * upper_excess
    upper = upper - fast_runoff
    upper_runoff = p["parK1"] * upper
    upper = upper - upper_runoff
    lower = lower + percolation
    lower_runoff = p["parK2"] * lower
    lower = lower - lower_runoff

    raw_runoff = fast_runoff + upper_runoff + lower_runoff
    stores = np.array([snowpack, meltwater, soil, upper, lower], dtype=np.float64)
    routing = np.concatenate(([raw_runoff], current[5:14]))
    return pack_state(stores, routing)


def simulate_adapter(
    rain: Sequence[float],
    pet: Sequence[float],
    temp: Sequence[float],
    params: dict,
    initial_state: dict | Sequence[float] | None = None,
) -> tuple[np.ndarray, np.ndarray]:
    """Simulate a daily series and retain every exact fifteen-state vector."""
    p = _validated_parameters(params)
    rain_values = np.asarray(rain, dtype=np.float64)
    pet_values = np.asarray(pet, dtype=np.float64)
    temp_values = np.asarray(temp, dtype=np.float64)
    if rain_values.ndim != 1 or rain_values.shape != pet_values.shape or rain_values.shape != temp_values.shape:
        raise ValueError("rain, pet, and temp must be one-dimensional arrays with identical shape")
    if not np.all(np.isfinite(np.concatenate((rain_values, pet_values, temp_values)))):
        raise ValueError("forcing arrays must contain only finite values")

    if initial_state is None or isinstance(initial_state, dict):
        state = initial_state_vector(p, initial_state)
    else:
        state = _as_finite_vector(initial_state, len(STATE_NAMES), "initial_state").copy()

    states = np.empty((len(rain_values), len(STATE_NAMES)), dtype=np.float64)
    discharge = np.empty(len(rain_values), dtype=np.float64)
    for day in range(len(rain_values)):
        state = advance_state(state, rain_values[day], pet_values[day], temp_values[day], p)
        states[day] = state
        discharge[day] = routed_discharge(state, p["lag_time"])
    return discharge, states


def routed_discharge(state: Sequence[float], lag_time: float) -> float:
    """Return routed discharge from a post-transition fifteen-state vector."""
    vector = _as_finite_vector(state, len(STATE_NAMES), "state")
    lag = float(lag_time)
    if not np.isfinite(lag) or lag < 1.0 or lag > 10.0:
        raise ValueError(f"lag_time must be finite and within frozen v1 bounds [1, 10], got {lag_time!r}")
    n_lag = int(np.ceil(lag))
    weights = np.arange(n_lag, 0, -1, dtype=np.float64)
    weights /= weights.sum()
    routing = vector[len(HYDRO_STATE_NAMES):len(HYDRO_STATE_NAMES) + n_lag]
    return float(weights @ routing)
