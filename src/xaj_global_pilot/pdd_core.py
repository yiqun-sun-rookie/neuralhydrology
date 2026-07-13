"""PDD (Positive Degree Day) 融雪模块。

移植自 forecast_system_lite/src/kernels/core/hydro_model/process_model/positive_degree_day/pdd_fixed.py
修正了 ice melt bug，保持原始实现不变。

状态向量: [snow_depth_m, ice_depth_m, last_temp_C]
输入: temp (°C), prec (mm)
输出: runoff (m)  ← 注意单位是米！
"""
import numpy as np


PDD_NOICE_PARAM_BOUNDS = {
    "pdd_factor_snow": (0.5, 10.0),
    "refreeze_snow": (0.0, 0.5),
    "temp_snow": (-3.0, 1.0),
    "temp_rain": (0.5, 4.0),
}
PDD_NOICE_PARAM_NAMES = list(PDD_NOICE_PARAM_BOUNDS.keys())


def _get_param(v):
    if isinstance(v, np.ndarray):
        return v
    elif hasattr(v, "to_numpy"):
        return v.to_numpy()
    return np.array(v)


def pdd_noice_step_mm(
    snow_depth_mm: float,
    temp_c: float,
    prec_mm: float,
    pdd_factor_snow: float,
    refreeze_snow: float,
    temp_snow: float,
    temp_rain: float,
) -> tuple[float, float]:
    """PDD-noice scalar step in mm.

    This is the shared reference snow front end for CAMELS-US conceptual
    comparisons where glacier ice storage is not initialized. It matches the
    zero-ice behavior of ``pdd_step`` and the GR4J no-ice PDD wrapper.
    """
    snow_frac = (temp_rain - temp_c) / (temp_rain - temp_snow + 1e-12)
    snow_frac = min(1.0, max(0.0, snow_frac))
    snowfall = prec_mm * snow_frac
    rainfall = prec_mm - snowfall

    snow_depth_mm = snow_depth_mm + snowfall
    pdd = temp_c if temp_c > 0.0 else 0.0
    pot_melt = pdd_factor_snow * pdd
    actual_melt = min(snow_depth_mm, pot_melt)
    refrozen = actual_melt * refreeze_snow
    snow_depth_mm = snow_depth_mm - actual_melt + refrozen
    if snow_depth_mm < 0.0:
        snow_depth_mm = 0.0
    liquid_mm = actual_melt - refrozen + rainfall
    return float(snow_depth_mm), float(liquid_mm)


def simulate_pdd_noice_mm(
    prec_mm: np.ndarray,
    temp_c: np.ndarray,
    param_dict: dict,
    initial_snow_mm: float = 0.0,
) -> tuple[np.ndarray, np.ndarray]:
    """Run the shared no-ice PDD reference over a series in mm."""
    prec_mm = np.asarray(prec_mm, dtype=np.float64)
    temp_c = np.asarray(temp_c, dtype=np.float64)
    snow = float(initial_snow_mm)
    runoff = np.zeros_like(prec_mm, dtype=np.float64)
    snow_store = np.zeros_like(prec_mm, dtype=np.float64)
    for i in range(prec_mm.size):
        snow, runoff[i] = pdd_noice_step_mm(
            snow,
            float(temp_c[i]),
            float(prec_mm[i]),
            float(param_dict["pdd_factor_snow"]),
            float(param_dict["refreeze_snow"]),
            float(param_dict["temp_snow"]),
            float(param_dict["temp_rain"]),
        )
        snow_store[i] = snow
    return runoff, snow_store


def pdd_step(
    state: np.ndarray,
    temp: np.ndarray,
    prec: np.ndarray,
    param_dict: dict,
) -> tuple[np.ndarray, np.ndarray]:
    """PDD 单步计算（矢量化）。

    Args:
        state: (N, 3) — [snow_depth_m, ice_depth_m, last_temp_C]
        temp:  (N,) — 日均温 (°C)
        prec:  (N,) — 日降水 (mm)
        param_dict: PDD 参数

    Returns:
        new_state: (N, 3)
        runoff: (N,) 单位为 **米**
    """
    pdd_factor_snow = _get_param(param_dict["pdd_factor_snow"])
    pdd_factor_ice = _get_param(param_dict["pdd_factor_ice"])
    refreeze_snow = _get_param(param_dict["refreeze_snow"])
    refreeze_ice = _get_param(param_dict["refreeze_ice"])
    temp_snow = _get_param(param_dict["temp_snow"])
    temp_rain = _get_param(param_dict["temp_rain"])

    snow_depth = state[:, 0].copy()
    ice_depth = state[:, 1].copy()

    prec_m = prec / 1000.0  # mm -> m

    # 1. 雨雪分离
    snow_frac = np.clip((temp_rain - temp) / (temp_rain - temp_snow + 1e-12), 0, 1)
    snowfall = snow_frac * prec_m
    rainfall = prec_m - snowfall

    # 2. 积雪
    snow_depth += snowfall

    # 3. 正积温
    pdd = np.maximum(temp, 0.0)

    # 4. 融雪
    pot_snow_melt = pdd_factor_snow * pdd / 1000.0  # m/day
    actual_snow_melt = np.minimum(snow_depth, pot_snow_melt)

    # 5. 融冰（剩余能量）— 修正版: min(ice_melt, ice_depth)
    remaining_energy = (pot_snow_melt - actual_snow_melt) * 1000.0  # mm
    ice_melt = remaining_energy * pdd_factor_ice / (pdd_factor_snow + 1e-12) / 1000.0  # m
    ice_melt_net = np.minimum(ice_melt, ice_depth)

    # 6. 更新积雪/冰 + 重冻结
    snow_depth -= actual_snow_melt
    refrozen_snow = actual_snow_melt * refreeze_snow
    snow_depth += refrozen_snow

    ice_depth -= ice_melt_net
    refrozen_ice = ice_melt_net * refreeze_ice
    ice_depth += refrozen_ice

    # 7. 产流
    total_melt = actual_snow_melt + ice_melt_net
    runoff = total_melt - refrozen_snow - refrozen_ice + rainfall

    # 8. 组装状态
    new_state = np.column_stack([
        np.maximum(snow_depth, 0),
        np.maximum(ice_depth, 0),
        temp,
    ])
    return new_state, runoff
