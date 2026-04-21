"""消融实验 2：XAJ + HBV 式幂律产流。

将 XAJ 的 B 曲线蓄满产流替换为 HBV 式 R = PE × (W/WM)^beta_r，
保持三层蒸发 + 三水源划分 + 三段汇流不变。

目的：验证 B 曲线产流机制是否是 XAJ vs HBV 差距的主要来源。

参数变化：去掉 b 和 imp（仅用于 B 曲线），新增 beta_r = 13 参数。
"""
import os as _os
try:
    if _os.environ.get("DISABLE_NUMBA") == "1":
        raise ImportError("Disabled via env")
    from numba import njit
    _HAS_NUMBA = True
except Exception:
    _HAS_NUMBA = False
    def njit(*args, **kwargs):
        def wrap(func):
            return func
        return wrap

import numpy as np
from typing import Tuple

from .xaj_numba import (
    redistribute_soil_water_numba,
    free_water_numba,
    update_soil_layers_numba,
    update_q_numba,
    pdd_step_numba,
)


# ===================================================================
# 替换的产流模块：HBV 式幂律产流
# ===================================================================

@njit(cache=True, fastmath=True)
def calc_runoff_power_numba(w, wm, beta_r, pe):
    """HBV 式幂律产流：R = PE × (W/WM)^beta_r。

    替代原 B 曲线 calc_runoff_numba。
    - 当 PE > 0 时按幂律分配产流
    - 当 PE <= 0 时不产流
    """
    wm_safe = np.maximum(wm, 1e-12)
    s_ratio = np.clip(w / wm_safe, 0.0, 1.0)
    runoff = np.where(
        pe > 0.0,
        pe * np.power(s_ratio, beta_r),
        0.0,
    )
    return runoff


# ===================================================================
# XAJ + 幂律产流 步进
# ===================================================================

@njit(cache=True, fastmath=True)
def xaj_power_runoff_step_numba(state, rain, pet, xaj_pars):
    """XAJ 单步，产流替换为 HBV 式幂律。

    state: (N, 8) [W, WU, WL, WD, S, QS, QI, QG]
    xaj_pars: tuple(16) — 去掉 b/imp/wmm，新增 beta_r
        (kc, ki, kg, cs, ci, cg, wum, wlm, wdm, sm, cpar, ex, uf, ms, beta_r, _dummy)
    """
    kc, ki, kg, cs, ci_, cg_, wum, wlm, wdm, sm, cpar, ex, uf, ms, beta_r, _dummy = xaj_pars

    W = state[:, 0]
    WU = state[:, 1]
    WL = state[:, 2]
    WD = state[:, 3]
    S = state[:, 4]
    QS = state[:, 5]
    QI = state[:, 6]
    QG = state[:, 7]

    wm = wum + wlm + wdm
    W_adj, WU_adj, WL_adj, WD_adj = redistribute_soil_water_numba(
        W, WU, WL, WD, wm, wum, wlm, wdm)

    ep = pet * kc
    pe = rain - ep

    # HBV 式幂律产流（替代 B 曲线）
    runoff_soil = calc_runoff_power_numba(W_adj, wm, beta_r, pe)

    # 三层蒸发（不变）
    W_new, WU_new, WL_new, WD_new, evap = update_soil_layers_numba(
        WU_adj, WL_adj, WD_adj, runoff_soil, rain, ep, wum, wlm, wdm, cpar)

    # 三水源划分（不变）
    S_new, RS, RI, RG, fr = free_water_numba(
        S, runoff_soil, pe, ki, kg, ms, sm, ex)

    # 三段汇流（不变）
    QS_new, QI_new, QG_new = update_q_numba(
        QS, QI, QG, RS, RI, RG, cs, ci_, cg_, uf)

    new_state = np.empty_like(state)
    new_state[:, 0] = W_new
    new_state[:, 1] = WU_new
    new_state[:, 2] = WL_new
    new_state[:, 3] = WD_new
    new_state[:, 4] = S_new
    new_state[:, 5] = QS_new
    new_state[:, 6] = QI_new
    new_state[:, 7] = QG_new

    return new_state


# ===================================================================
# 高层模拟
# ===================================================================

def simulate_xaj_power_runoff(rain, pet, params, initial_state=None):
    """XAJ + HBV式幂律产流。

    params: 13 个参数（去掉 b, imp；新增 beta_r）
        kc, wum, wlm, wdm, sm, c, ex, ki, kg, cs, ci, cg, beta_r
    """
    T = len(rain)
    ms = params['sm'] * (1 + params['ex'])

    xaj_pars = tuple(np.array([np.float64(v)]) for v in (
        params['kc'], params['ki'], params['kg'],
        params['cs'], params['ci'], params['cg'],
        params['wum'], params['wlm'], params['wdm'],
        params['sm'], params['c'],
        params['ex'], 1.0, ms,
        params['beta_r'], 0.0,  # dummy to keep tuple length even
    ))

    if initial_state is not None:
        state = initial_state.copy().astype(np.float64)
    else:
        state = np.array([[
            params['wum'] * 0.5 + params['wlm'] * 0.5 + params['wdm'] * 0.5,
            params['wum'] * 0.5, params['wlm'] * 0.5, params['wdm'] * 0.5,
            params['sm'] * 0.5, 0.0, 0.0, 0.0,
        ]])

    q = np.zeros(T)
    for t in range(T):
        r_t = np.array([rain[t]])
        p_t = np.array([pet[t]])
        state = xaj_power_runoff_step_numba(state, r_t, p_t, xaj_pars)
        q[t] = state[0, 5] + state[0, 6] + state[0, 7]

    return np.maximum(q, 0.0), state.copy()


# ===================================================================
# PDD + XAJ-PowerRunoff 耦合
# ===================================================================

@njit(cache=True, fastmath=True)
def coupled_pdd_xaj_power_runoff_step_numba(joint_state, temp, rain, snow, pet, pdd_pars, xaj_pars):
    """PDD + XAJ-PowerRunoff 耦合单步。

    joint_state: (N, 11) [snow_depth, ice_depth, last_temp, W, WU, WL, WD, S, QS, QI, QG]
    xaj_pars: tuple(16) — 去掉 b/imp/wmm，新增 beta_r
    """
    fsnow, fice, rfsnow, rfice = pdd_pars
    kc, ki, kg, cs, ci_, cg_, wum, wlm, wdm, sm, cpar, ex, uf, ms, beta_r, _dummy = xaj_pars

    pdd_state = joint_state[:, :3]
    W = joint_state[:, 3]; WU = joint_state[:, 4]; WL = joint_state[:, 5]; WD = joint_state[:, 6]
    S = joint_state[:, 7]; QS = joint_state[:, 8]; QI = joint_state[:, 9]; QG = joint_state[:, 10]

    new_pdd_state, runoff_pdd = pdd_step_numba(
        pdd_state, temp, rain, snow, fsnow, fice, rfsnow, rfice)

    wm = wum + wlm + wdm
    W_adj, WU_adj, WL_adj, WD_adj = redistribute_soil_water_numba(W, WU, WL, WD, wm, wum, wlm, wdm)

    ep = pet * kc
    pe = runoff_pdd - ep

    # HBV 式幂律产流
    runoff_soil = calc_runoff_power_numba(W_adj, wm, beta_r, pe)

    # 三层蒸发（不变）
    W_new, WU_new, WL_new, WD_new, evap = update_soil_layers_numba(
        WU_adj, WL_adj, WD_adj, runoff_soil, runoff_pdd, ep, wum, wlm, wdm, cpar)

    S_new, RS, RI, RG, fr = free_water_numba(S, runoff_soil, pe, ki, kg, ms, sm, ex)
    QS_new, QI_new, QG_new = update_q_numba(QS, QI, QG, RS, RI, RG, cs, ci_, cg_, uf)

    new_state = np.empty_like(joint_state)
    new_state[:, 0] = new_pdd_state[:, 0]
    new_state[:, 1] = new_pdd_state[:, 1]
    new_state[:, 2] = new_pdd_state[:, 2]
    new_state[:, 3] = W_new; new_state[:, 4] = WU_new
    new_state[:, 5] = WL_new; new_state[:, 6] = WD_new
    new_state[:, 7] = S_new; new_state[:, 8] = QS_new
    new_state[:, 9] = QI_new; new_state[:, 10] = QG_new
    return new_state, runoff_pdd


def simulate_pdd_xaj_power_runoff(rain, pet, temp, params, initial_state=None):
    """PDD + XAJ-PowerRunoff 耦合模拟。19 参数 (6 PDD + 13 XAJ-PowerRunoff)。"""
    T = len(rain)
    ms = params['sm'] * (1 + params['ex'])

    xaj_pars = tuple(np.array([np.float64(v)]) for v in (
        params['kc'], params['ki'], params['kg'],
        params['cs'], params['ci'], params['cg'],
        params['wum'], params['wlm'], params['wdm'],
        params['sm'], params['c'],
        params['ex'], 1.0, ms,
        params['beta_r'], 0.0,
    ))

    pdd_pars = tuple(np.array([np.float64(params[k])]) for k in (
        'pdd_factor_snow', 'pdd_factor_ice', 'refreeze_snow', 'refreeze_ice'))

    temp_snow = params.get('temp_snow', 0.0)
    temp_rain = params.get('temp_rain', 2.0)

    if initial_state is not None:
        state = initial_state.copy().astype(np.float64)
    else:
        state = np.array([[
            0.0, 0.0, 0.0,
            params['wum'] * 0.5 + params['wlm'] * 0.5 + params['wdm'] * 0.5,
            params['wum'] * 0.5, params['wlm'] * 0.5, params['wdm'] * 0.5,
            params['sm'] * 0.5, 0.0, 0.0, 0.0,
        ]])

    q = np.zeros(T)
    for t in range(T):
        t_val = temp[t]
        snow_frac = np.clip((temp_rain - t_val) / (temp_rain - temp_snow + 1e-12), 0.0, 1.0)
        snow_t = np.array([rain[t] * snow_frac])
        rain_t = np.array([rain[t] * (1.0 - snow_frac)])
        pet_t = np.array([pet[t]])
        temp_t = np.array([t_val])
        state, _ = coupled_pdd_xaj_power_runoff_step_numba(
            state, temp_t, rain_t, snow_t, pet_t, pdd_pars, xaj_pars)
        q[t] = state[0, 8] + state[0, 9] + state[0, 10]

    return np.maximum(q, 0.0), state.copy()
