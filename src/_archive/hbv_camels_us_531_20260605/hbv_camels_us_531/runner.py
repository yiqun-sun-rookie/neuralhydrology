from contextlib import contextmanager
from dataclasses import dataclass, field
from typing import Dict, Optional

import numpy as np
import pandas as pd

from src.hbv_camels_us_531.structure import build_fixed_hbv_structure
from src.hbv_camels_us_531.hbv_model import calibrate_hbv, simulate_hbv
from src.hydroagent.data_loading import load_camels_basin
from src.hydroagent import environment as hydro_environment
from src.hydroagent.environment import SuperflexEnv

from src.hbv_camels_us_531.config import (
    TEST_END_DATE,
    TEST_START_DATE,
    TRAIN_END_DATE,
    TRAIN_START_DATE,
    VALIDATION_END_DATE,
    VALIDATION_START_DATE,
)


@dataclass
class BasinRunResult:
    basin_id: str
    train_nse: Optional[float] = None
    validation_nse: Optional[float] = None
    test_nse: Optional[float] = None
    bounds_profile: str = "primary"
    status: str = "ok"
    error: str = ""
    best_params: Dict[str, float] = field(default_factory=dict)


_PRIMARY_HBV_BOUND_OVERRIDES = {
    "UnsaturatedReservoir": {
        "beta": (1.0, 5.0),
    },
}

_FALLBACK_HBV_BOUND_OVERRIDES = {
    **_PRIMARY_HBV_BOUND_OVERRIDES,
    "PowerReservoir": {
        "alpha": (1.0, 2.5),
    },
}


def split_periods() -> Dict[str, tuple[str, str]]:
    return {
        "train": (TRAIN_START_DATE, TRAIN_END_DATE),
        "validation": (VALIDATION_START_DATE, VALIDATION_END_DATE),
        "test": (TEST_START_DATE, TEST_END_DATE),
    }


def _compute_nse(obs, sim) -> float:
    common_idx = obs.index.intersection(sim.index)
    if len(common_idx) == 0:
        raise ValueError("Observed and simulated discharge do not share timestamps.")

    obs_values = np.asarray(obs.loc[common_idx], dtype=float)
    sim_values = np.asarray(sim.loc[common_idx], dtype=float)
    if not np.isfinite(obs_values).all() or not np.isfinite(sim_values).all():
        raise ValueError("Non-finite discharge encountered during NSE computation.")

    denominator = np.sum((obs_values - np.mean(obs_values)) ** 2)
    if denominator <= 0:
        raise ValueError("Observed discharge variance is zero; NSE is undefined.")

    numerator = np.sum((sim_values - obs_values) ** 2)
    return float(1.0 - numerator / denominator)


def _compute_nse_arrays(obs: np.ndarray, sim: np.ndarray) -> float:
    mask = np.isfinite(obs) & np.isfinite(sim)
    if mask.sum() < 10:
        raise ValueError("Too few valid data points for NSE computation.")
    o, s = obs[mask], sim[mask]
    denom = np.sum((o - o.mean()) ** 2)
    if denom <= 0:
        raise ValueError("Observed discharge variance is zero.")
    return float(1.0 - np.sum((s - o) ** 2) / denom)


def _validate_period_inputs(period_name: str, forcing: pd.DataFrame, obs: pd.Series) -> None:
    if forcing.empty:
        raise ValueError(f"{period_name} forcing data is empty.")
    if obs.empty:
        raise ValueError(f"{period_name} observed discharge is empty.")
    if not np.isfinite(forcing.to_numpy(dtype=float)).all():
        raise ValueError(f"{period_name} forcing contains non-finite values.")
    if not np.isfinite(np.asarray(obs, dtype=float)).all():
        raise ValueError(f"{period_name} observed discharge contains non-finite values.")


def _validate_calibration_result(train_result: dict) -> dict:
    if "nse" not in train_result:
        raise ValueError("Calibration did not return an NSE value.")
    train_nse = float(train_result["nse"])
    if not np.isfinite(train_nse):
        raise ValueError("Calibration returned a non-finite NSE.")

    best_params = train_result.get("optimized_params") or {}
    if not isinstance(best_params, dict):
        raise ValueError("Calibration did not return a parameter dictionary.")
    if any(not np.isfinite(float(value)) for value in best_params.values()):
        raise ValueError("Calibration returned non-finite parameter values.")

    return {"train_nse": train_nse, "best_params": best_params}


@contextmanager
def _temporary_hbv_calibration_bounds(bound_overrides: Dict[str, Dict[str, tuple[float, float]]]):
    original_bounds = {}
    try:
        for component_name, overrides in bound_overrides.items():
            component_bounds = hydro_environment._REGISTRY[component_name]["bounds"]
            original_bounds[component_name] = {name: component_bounds[name] for name in overrides}
            component_bounds.update(overrides)
        yield
    finally:
        for component_name, bounds in original_bounds.items():
            hydro_environment._REGISTRY[component_name]["bounds"].update(bounds)


def _run_single_basin_attempt(
    basin_id: str,
    data_root,
    bounds_profile: str,
    bound_overrides: Dict[str, Dict[str, tuple[float, float]]],
) -> BasinRunResult:
    with _temporary_hbv_calibration_bounds(bound_overrides):
        periods = split_periods()
        structure = build_fixed_hbv_structure()
        env = SuperflexEnv()
        env.parse_structure(structure)

        train_forcing, train_obs, _ = load_camels_basin(
            basin_id, data_root=data_root, start_date=periods["train"][0], end_date=periods["train"][1]
        )
        _validate_period_inputs("train", train_forcing, train_obs)
        train_result = env.auto_calibrate(train_forcing, train_obs)
        train_metadata = _validate_calibration_result(train_result)
        best_params = train_metadata["best_params"]

        validation_forcing, validation_obs, _ = load_camels_basin(
            basin_id, data_root=data_root, start_date=periods["validation"][0], end_date=periods["validation"][1]
        )
        _validate_period_inputs("validation", validation_forcing, validation_obs)
        validation_sim = env.run_simulation(validation_forcing, params=best_params)

        test_forcing, test_obs, _ = load_camels_basin(
            basin_id, data_root=data_root, start_date=periods["test"][0], end_date=periods["test"][1]
        )
        _validate_period_inputs("test", test_forcing, test_obs)
        test_sim = env.run_simulation(test_forcing, params=best_params)

        return BasinRunResult(
            basin_id=basin_id,
            train_nse=train_metadata["train_nse"],
            validation_nse=_compute_nse(validation_obs, validation_sim),
            test_nse=_compute_nse(test_obs, test_sim),
            bounds_profile=bounds_profile,
            best_params=best_params,
        )


def _extract_arrays(forcing: pd.DataFrame, obs: pd.Series):
    """Extract rain, pet, temp arrays from forcing DataFrame."""
    rain = np.nan_to_num(forcing['prcp'].values.astype(np.float64), nan=0.0)

    pet = np.zeros(len(rain))
    for col in ('ep', 'pet', 'evap'):
        if col in forcing.columns:
            pet = np.nan_to_num(forcing[col].values.astype(np.float64), nan=0.0)
            break

    temp = np.zeros(len(rain))
    for col in ('tmean', 'tavg', 'temp', 'temperature'):
        if col in forcing.columns:
            temp = np.nan_to_num(forcing[col].values.astype(np.float64), nan=0.0)
            break
    if 'tmax' in forcing.columns and 'tmin' in forcing.columns:
        temp = np.nan_to_num(((forcing['tmax'] + forcing['tmin']) / 2).values.astype(np.float64), nan=0.0)

    return rain, pet, temp, obs.values.astype(np.float64)


def _run_numpy_fallback(basin_id: str, data_root) -> BasinRunResult:
    """Fallback: pure NumPy HBV when SuperflexPy solver crashes."""
    periods = split_periods()

    train_f, train_o, _ = load_camels_basin(
        basin_id, data_root=data_root, start_date=periods["train"][0], end_date=periods["train"][1],
    )
    val_f, val_o, _ = load_camels_basin(
        basin_id, data_root=data_root, start_date=periods["validation"][0], end_date=periods["validation"][1],
    )
    test_f, test_o, _ = load_camels_basin(
        basin_id, data_root=data_root, start_date=periods["test"][0], end_date=periods["test"][1],
    )

    train_rain, train_pet, train_temp, train_obs_arr = _extract_arrays(train_f, train_o)
    val_rain, val_pet, val_temp, _ = _extract_arrays(val_f, val_o)
    test_rain, test_pet, test_temp, _ = _extract_arrays(test_f, test_o)

    cal_result = calibrate_hbv(train_rain, train_pet, train_temp, train_obs_arr)
    best_params = cal_result['optimized_params']
    train_nse = cal_result['nse']

    if not np.isfinite(train_nse) or train_nse <= -900:
        raise ValueError("NumPy HBV calibration failed to converge")

    _, train_final = simulate_hbv(train_rain, train_pet, train_temp, best_params)
    val_q, val_final = simulate_hbv(val_rain, val_pet, val_temp, best_params, initial_state=train_final)
    test_q, _ = simulate_hbv(test_rain, test_pet, test_temp, best_params, initial_state=val_final)

    return BasinRunResult(
        basin_id=basin_id,
        train_nse=train_nse,
        validation_nse=_compute_nse_arrays(val_o.values.astype(np.float64), val_q),
        test_nse=_compute_nse_arrays(test_o.values.astype(np.float64), test_q),
        bounds_profile="numpy_fallback",
        best_params=best_params,
    )


def run_single_basin(basin_id: str, data_root=None) -> BasinRunResult:
    # Try SuperflexPy (primary → fallback bounds)
    primary_error = None
    try:
        return _run_single_basin_attempt(basin_id, data_root, "primary", _PRIMARY_HBV_BOUND_OVERRIDES)
    except Exception as exc:
        primary_error = str(exc)

    try:
        return _run_single_basin_attempt(basin_id, data_root, "fallback", _FALLBACK_HBV_BOUND_OVERRIDES)
    except Exception as exc:
        sfpy_error = f"primary: {primary_error}; fallback: {exc}"

    # SuperflexPy failed → NumPy fallback
    try:
        return _run_numpy_fallback(basin_id, data_root)
    except Exception as exc:
        return BasinRunResult(
            basin_id=basin_id,
            status="failed",
            error=f"superflexpy: [{sfpy_error}]; numpy: {exc}",
        )
