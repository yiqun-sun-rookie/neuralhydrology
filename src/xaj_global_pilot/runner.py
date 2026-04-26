from pathlib import Path
import math

import numpy as np
import pandas as pd

from neuralhydrology.datasetzoo.caravan import load_caravan_timeseries
from src.hydroagent.data_loading import load_camels_basin
# SuperflexEnv pulls in superflexpy, which is required for HBV / GR4J only.
# Tolerate the import failure so xaj / xaj_pdd / xaj_smooth_et can still run
# in superflexpy-less environments (e.g. local dev).
try:
    from src.hydroagent.environment import SuperflexEnv
    _HAS_SUPERFLEXPY = True
except (ImportError, ModuleNotFoundError):
    SuperflexEnv = None  # type: ignore[assignment,misc]
    _HAS_SUPERFLEXPY = False
from src.xaj_global_pilot.config import (
    REPRO_FORCING,
    V02_FORCING,
    repro_split_periods,
    split_periods,
)
from src.xaj_global_pilot.metrics import compute_metrics
from src.xaj_global_pilot.model_catalog import get_model_specs
from src.xaj_global_pilot.xaj_model import (
    calibrate_xaj, simulate_xaj, calibrate_pdd_xaj, simulate_pdd_xaj,
    calibrate_xaj_smooth_et,
)
from src.xaj_global_pilot.xaj_numba_smooth_et import simulate_xaj_smooth_et


# Map protocol name -> (periods_fn, calibration_key, evaluation_key, period_label, default_forcing).
# `period_label` is the value written to the result row's `period` column.
# `default_forcing` is the CAMELS-US forcing dataset that the protocol expects;
# the chunk runner can override it via --forcing.
_PROTOCOLS = {
    "v02": (split_periods, "train", "test", "test", V02_FORCING),
    "repro_v01": (repro_split_periods, "calibration", "evaluation", "evaluation", REPRO_FORCING),
}


def run_single_model_basin(
    basin_id: str,
    model: str,
    data_root=None,
    calibration_trials: int = 2000,
    n_restarts: int = 3,
    protocol: str = "v02",
    forcing: str | None = None,
) -> dict:
    specs = _flatten_model_specs()
    if model not in specs:
        raise ValueError(f"Unknown pilot model '{model}'")
    spec = specs[model]

    if protocol not in _PROTOCOLS:
        raise ValueError(f"Unknown protocol '{protocol}'. Expected one of {list(_PROTOCOLS)}.")
    periods_fn, calib_key, eval_key, period_label, default_forcing = _PROTOCOLS[protocol]
    periods = periods_fn()
    forcing_to_use = forcing if forcing is not None else default_forcing

    try:
        train_forcing, train_obs = _load_period(
            basin_id, data_root, *periods[calib_key], forcing=forcing_to_use
        )
        test_forcing, test_obs = _load_period(
            basin_id, data_root, *periods[eval_key], forcing=forcing_to_use
        )

        if model == "xaj":
            metrics = _run_numpy_xaj(train_forcing, train_obs, test_forcing, test_obs, calibration_trials, n_restarts)
        elif model == "xaj_smooth_et":
            metrics = _run_numpy_xaj_smooth_et(
                train_forcing, train_obs, test_forcing, test_obs, calibration_trials, n_restarts
            )
        elif model == "xaj_pdd":
            metrics = _run_numpy_pdd_xaj(
                train_forcing, train_obs, test_forcing, test_obs, calibration_trials, n_restarts
            )
        else:
            structure = specs[model]["structure_builder"]()
            metrics = _run_superflexpy(
                structure, train_forcing, train_obs, test_forcing, test_obs, calibration_trials, n_restarts
            )

        return {
            "basin_id": basin_id,
            "model": model,
            "period": period_label,
            **metrics,
            "parameter_count": spec["parameter_count"],
            "solver_name": spec["solver_name"],
            "family": spec["family"],
            "run_status": "success",
            "error_message": "",
        }
    except Exception as exc:
        return {
            "basin_id": basin_id,
            "model": model,
            "period": period_label,
            "nse": pd.NA,
            "kge": pd.NA,
            "bias": pd.NA,
            "peak_bias": pd.NA,
            "lowflow_bias": pd.NA,
            "parameter_count": spec["parameter_count"],
            "solver_name": spec["solver_name"],
            "family": spec["family"],
            "run_status": "failed",
            "error_message": str(exc),
        }


def _flatten_model_specs() -> dict:
    grouped = get_model_specs()
    flat = {}
    for group in grouped.values():
        flat.update(group)
    return flat


# ---------------------------------------------------------------------------
# 经典新安江模型 (NumPy)
# ---------------------------------------------------------------------------

def _run_numpy_xaj(train_forcing, train_obs, test_forcing, test_obs, calibration_trials, n_restarts):
    """使用从 forecast_system_lite 移植的经典新安江模型。"""
    train_rain, train_pet = _extract_rain_pet(train_forcing)
    test_rain, test_pet = _extract_rain_pet(test_forcing)
    train_obs_arr = train_obs.values.astype(np.float64)

    # 率定
    result = calibrate_xaj(
        train_rain, train_pet, train_obs_arr, n_trials=calibration_trials, n_restarts=n_restarts
    )
    best_params = result.get('optimized_params')
    if best_params is None:
        raise RuntimeError("XAJ calibration returned no parameters")

    # 用率定参数跑完整训练期，取末状态作为测试期初始条件
    _, final_state = simulate_xaj(train_rain, train_pet, best_params)

    # 在测试期用训练末状态启动
    test_q, _ = simulate_xaj(test_rain, test_pet, best_params, initial_state=final_state)
    test_sim = pd.Series(test_q, index=test_obs.index, name='qsim')

    return compute_metrics(test_obs, test_sim)


def _run_numpy_xaj_smooth_et(train_forcing, train_obs, test_forcing, test_obs, calibration_trials, n_restarts):
    """消融实验：XAJ + HBV式平滑蒸发。"""
    train_rain, train_pet = _extract_rain_pet(train_forcing)
    test_rain, test_pet = _extract_rain_pet(test_forcing)
    train_obs_arr = train_obs.values.astype(np.float64)

    result = calibrate_xaj_smooth_et(
        train_rain, train_pet, train_obs_arr, n_trials=calibration_trials, n_restarts=n_restarts
    )
    best_params = result.get('optimized_params')
    if best_params is None:
        raise RuntimeError("XAJ-SmoothET calibration returned no parameters")

    _, final_state = simulate_xaj_smooth_et(train_rain, train_pet, best_params)
    test_q, _ = simulate_xaj_smooth_et(test_rain, test_pet, best_params, initial_state=final_state)
    test_sim = pd.Series(test_q, index=test_obs.index, name='qsim')

    return compute_metrics(test_obs, test_sim)


def _run_numpy_pdd_xaj(train_forcing, train_obs, test_forcing, test_obs, calibration_trials, n_restarts):
    """PDD 融雪 + 经典新安江耦合模型。"""
    train_rain, train_pet, train_temp = _extract_rain_pet_temp(train_forcing)
    test_rain, test_pet, test_temp = _extract_rain_pet_temp(test_forcing)
    train_obs_arr = train_obs.values.astype(np.float64)

    result = calibrate_pdd_xaj(
        train_rain, train_pet, train_temp, train_obs_arr,
        n_trials=calibration_trials, n_restarts=n_restarts,
    )
    best_params = result.get('optimized_params')
    if best_params is None:
        raise RuntimeError("PDD+XAJ calibration returned no parameters")

    _, final_state = simulate_pdd_xaj(train_rain, train_pet, train_temp, best_params)
    test_q, _ = simulate_pdd_xaj(test_rain, test_pet, test_temp, best_params, initial_state=final_state)
    test_sim = pd.Series(test_q, index=test_obs.index, name='qsim')

    return compute_metrics(test_obs, test_sim)


def _extract_rain_pet_temp(forcing: pd.DataFrame) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    rain, pet = _extract_rain_pet(forcing)
    if 'tmean' in forcing.columns:
        temp = np.nan_to_num(forcing['tmean'].values.astype(np.float64), 0.0)
    else:
        temp = np.zeros(len(rain))
    return rain, pet, temp


def _extract_rain_pet(forcing: pd.DataFrame) -> tuple[np.ndarray, np.ndarray]:
    rain = forcing['prcp'].values.astype(np.float64)
    for col in ('ep', 'pet', 'evap'):
        if col in forcing.columns:
            pet = forcing[col].values.astype(np.float64)
            return np.nan_to_num(rain, 0.0), np.nan_to_num(pet, 0.0)
    return np.nan_to_num(rain, 0.0), np.zeros(len(rain))


# ---------------------------------------------------------------------------
# SuperflexPy 路径 (xaj_pdd, hbv)
# ---------------------------------------------------------------------------

def _run_superflexpy(structure, train_forcing, train_obs, test_forcing, test_obs, calibration_trials, n_restarts):
    if not _HAS_SUPERFLEXPY:
        raise ImportError(
            "superflexpy is required for HBV / GR4J runs but is not importable in this environment."
        )
    calibration_env = _build_env(structure)
    if hasattr(calibration_env, "_calibrate_sfpy"):
        train_result = calibration_env._calibrate_sfpy(
            train_forcing, train_obs, n_trials=calibration_trials, n_restarts=n_restarts
        )
    else:
        train_result = calibration_env.auto_calibrate(
            train_forcing, train_obs, n_trials=calibration_trials, n_restarts=n_restarts
        )
    best_params = _select_best_params(train_result)
    test_env = _build_env(structure)
    test_sim = _run_test_simulation(test_env, test_forcing, best_params)
    return compute_metrics(test_obs, test_sim)


def _build_env(structure: dict):
    """Construct a SuperflexEnv around `structure`. Requires superflexpy."""
    env = SuperflexEnv()
    env.parse_structure(structure)
    return env


def _select_best_params(train_result: dict) -> dict | None:
    train_nse = train_result.get("nse")
    if train_nse is None or not math.isfinite(float(train_nse)) or float(train_nse) <= -900.0:
        return None

    best_params = train_result.get("optimized_params") or {}
    if not isinstance(best_params, dict):
        return None
    try:
        if any(not math.isfinite(float(value)) for value in best_params.values()):
            return None
    except (TypeError, ValueError):
        return None
    return best_params


def _run_test_simulation(env: SuperflexEnv, test_forcing: pd.DataFrame, best_params: dict | None) -> pd.Series:
    if not best_params:
        return env.run_simulation(test_forcing)

    try:
        sim = env.run_simulation(test_forcing, params=best_params)
        if isinstance(sim, pd.Series):
            sim_values = sim.to_numpy(dtype=float, copy=False)
            if not np.isfinite(sim_values).any():
                return _run_default_test_simulation(env, test_forcing)
        return sim
    except Exception:
        return _run_default_test_simulation(env, test_forcing)


def _run_default_test_simulation(env: SuperflexEnv, test_forcing: pd.DataFrame) -> pd.Series:
    structure = getattr(env, "structure_json", None)
    if structure:
        fallback_env = _build_env(structure)
        return fallback_env.run_simulation(test_forcing)
    return env.run_simulation(test_forcing)


# ---------------------------------------------------------------------------
# 数据加载
# ---------------------------------------------------------------------------

def _load_period(
    basin_id: str,
    data_root,
    start_date: str,
    end_date: str,
    forcing: str = "daymet",
) -> tuple[pd.DataFrame, pd.Series]:
    root = Path(data_root) if data_root is not None else None
    if root is not None and ((root / "timeseries").exists() or "caravan" in str(root).lower()):
        # Caravan path uses its own bundled forcing (ERA5 / FAO P-M); the
        # `forcing` arg is ignored here since Caravan does not offer the
        # daymet / maurer choice.
        return _load_caravan_period(basin_id, root, start_date, end_date)

    forcing_df, obs, _ = load_camels_basin(
        basin_id, data_root=data_root, start_date=start_date, end_date=end_date,
        forcing=forcing,
    )
    return forcing_df, obs


def _load_caravan_period(basin_id: str, data_root: Path, start_date: str, end_date: str) -> tuple[pd.DataFrame, pd.Series]:
    df = load_caravan_timeseries(data_dir=data_root, basin=basin_id).loc[start_date:end_date].copy()
    forcing = pd.DataFrame(index=df.index)
    forcing["prcp"] = df["total_precipitation_sum"]
    if "potential_evaporation_sum_ERA5_LAND" in df.columns:
        forcing["ep"] = df["potential_evaporation_sum_ERA5_LAND"]
    else:
        forcing["ep"] = df["potential_evaporation_sum_FAO_PENMAN_MONTEITH"]
    forcing["tmean"] = df["temperature_2m_mean"]
    forcing["ep"] = forcing["ep"].clip(lower=0.0)
    obs = df["streamflow"]

    aligned = pd.concat([forcing, obs.rename("streamflow")], axis=1).dropna(subset=["streamflow"])
    forcing = aligned[["prcp", "ep", "tmean"]]
    obs = aligned["streamflow"]
    return forcing, obs
