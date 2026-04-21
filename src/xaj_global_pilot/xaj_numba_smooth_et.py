"""消融实验：XAJ + HBV 式平滑蒸发。

将 XAJ 的三层阶梯蒸发替换为 HBV 式 ET = Ce × PET × (W/WM)^m，
保持 B 曲线产流 + 三水源划分 + 三段汇流不变。

目的：验证蒸发机制是否是 XAJ vs HBV 差距的主要来源。
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
    calc_runoff_numba,
    free_water_numba,
    update_q_numba,
    pdd_step_numba,
)


# ===================================================================
# 替换的蒸发模块：HBV 式平滑蒸发
# ===================================================================

@njit(cache=True, fastmath=True)
def update_soil_smooth_et_numba(
    wu, wl, wd, runoff, rain, ep, wum, wlm, wdm, ce, m_et
):
    """HBV 式平滑蒸发 + XAJ 三层土壤水更新。

    ET = Ce × EP × (W/WM)^m_et  ← 替代原三层阶梯蒸发
    剩余水量按 XAJ 三层分配逻辑更新。

    Parameters
    ----------
    ce : 蒸发效率系数 (类似 HBV 的 Ce，0.3-1.5)
    m_et : 蒸发非线性指数 (类似 HBV 的 m，0.001-0.5)

    Returns: (w, wu, wl, wd, evap)
    """
    wm = wum + wlm + wdm
    wm_safe = np.maximum(wm, 1e-12)
    w_total = wu + wl + wd

    # HBV 式蒸发: ET = Ce * EP * (W/WM)^m
    s_ratio = np.clip(w_total / wm_safe, 0.0, 1.0)
    actual_et = ce * ep * np.power(s_ratio, m_et)
    # 不能蒸发超过可用水量
    actual_et = np.minimum(actual_et, w_total)

    pe = rain - actual_et
    water_extra = np.maximum(pe - runoff, 0.0)

    new_wu = wu.copy()
    new_wl = wl.copy()
    new_wd = wd.copy()

    # 蒸发从三层按比例扣除
    for i in range(wu.size):
        if w_total[i] > 1e-12:
            ratio_u = new_wu[i] / w_total[i]
            ratio_l = new_wl[i] / w_total[i]
            ratio_d = new_wd[i] / w_total[i]
            new_wu[i] -= actual_et[i] * ratio_u
            new_wl[i] -= actual_et[i] * ratio_l
            new_wd[i] -= actual_et[i] * ratio_d

    # 入渗水量按 XAJ 逻辑填充三层
    mask_pos = water_extra > 0.0
    if mask_pos.any():
        idx = np.where(mask_pos)

        wu_plus = new_wu[idx] + water_extra[idx]
        over1 = wu_plus > wum[idx]
        new_wu[idx] = np.where(over1, wum[idx], wu_plus)
        we1 = np.where(over1, wu_plus - wum[idx], 0.0)

        wl_plus = new_wl[idx] + we1
        over2 = wl_plus > wlm[idx]
        new_wl[idx] = np.where(over2, wlm[idx], wl_plus)
        we2 = np.where(over2, wl_plus - wlm[idx], 0.0)

        wd_plus = new_wd[idx] + we2
        over3 = wd_plus > wdm[idx]
        new_wd[idx] = np.where(over3, wdm[idx], wd_plus)

    new_wu = np.clip(new_wu, 0.0, wum)
    new_wl = np.clip(new_wl, 0.0, wlm)
    new_wd = np.clip(new_wd, 0.0, wdm)

    w_new = new_wu + new_wl + new_wd
    return w_new, new_wu, new_wl, new_wd, actual_et


# ===================================================================
# XAJ + 平滑蒸发 步进
# ===================================================================

@njit(cache=True, fastmath=True)
def xaj_smooth_et_step_numba(state, rain, pet, xaj_pars):
    """XAJ 单步，蒸发替换为 HBV 式平滑函数。

    state: (N, 8) [W, WU, WL, WD, S, QS, QI, QG]
    xaj_pars: tuple(19) — 原 17 个 + ce + m_et
    """
    kc, ki, kg, cs, ci_, cg_, wum, wlm, wdm, sm, imp, cpar, b, ex, uf, wmm, ms, ce, m_et = xaj_pars

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
    pe = rain - ep  # 用于 B 曲线的 PE 仍基于原始 EP

    # B 曲线产流（不变）
    runoff_soil = calc_runoff_numba(W_adj, wmm, wm, b, pe)

    # 平滑蒸发 + 土壤更新（替换原三层蒸发）
    W_new, WU_new, WL_new, WD_new, evap = update_soil_smooth_et_numba(
        WU_adj, WL_adj, WD_adj, runoff_soil, rain, ep, wum, wlm, wdm, ce, m_et)

    S_new, RS, RI, RG, fr = free_water_numba(
        S, runoff_soil, pe, ki, kg, ms, sm, ex)

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

def simulate_xaj_smooth_et(rain, pet, params, initial_state=None):
    """XAJ + HBV式平滑蒸发。

    params: 原 14 个 XAJ 参数 + ce(蒸发效率) + m_et(蒸发非线性指数) = 16 个
    """
    T = len(rain)
    wm = params['wum'] + params['wlm'] + params['wdm']
    wmm = wm * (1 + params['b']) / (1 - params['imp'])
    ms = params['sm'] * (1 + params['ex'])

    xaj_pars = tuple(np.array([np.float64(v)]) for v in (
        params['kc'], params['ki'], params['kg'],
        params['cs'], params['ci'], params['cg'],
        params['wum'], params['wlm'], params['wdm'],
        params['sm'], params['imp'], params['c'],
        params['b'], params['ex'], 1.0, wmm, ms,
        params['ce'], params['m_et'],
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
        state = xaj_smooth_et_step_numba(state, r_t, p_t, xaj_pars)
        q[t] = state[0, 5] + state[0, 6] + state[0, 7]

    return np.maximum(q, 0.0), state.copy()


# ===================================================================
# PDD + XAJ-SmoothET 耦合
# ===================================================================

@njit(cache=True, fastmath=True)
def coupled_pdd_xaj_smooth_et_step_numba(joint_state, temp, rain, snow, pet, pdd_pars, xaj_pars):
    """PDD + XAJ-SmoothET 耦合单步。

    joint_state: (N, 11) [snow_depth, ice_depth, last_temp, W, WU, WL, WD, S, QS, QI, QG]
    xaj_pars: tuple(19) — 原 17 个 + ce + m_et
    """
    fsnow, fice, rfsnow, rfice = pdd_pars
    kc, ki, kg, cs, ci_, cg_, wum, wlm, wdm, sm, imp, cpar, b, ex, uf, wmm, ms, ce, m_et = xaj_pars

    pdd_state = joint_state[:, :3]
    W = joint_state[:, 3]; WU = joint_state[:, 4]; WL = joint_state[:, 5]; WD = joint_state[:, 6]
    S = joint_state[:, 7]; QS = joint_state[:, 8]; QI = joint_state[:, 9]; QG = joint_state[:, 10]

    new_pdd_state, runoff_pdd = pdd_step_numba(
        pdd_state, temp, rain, snow, fsnow, fice, rfsnow, rfice)

    wm = wum + wlm + wdm
    W_adj, WU_adj, WL_adj, WD_adj = redistribute_soil_water_numba(W, WU, WL, WD, wm, wum, wlm, wdm)

    ep = pet * kc
    pe = runoff_pdd - ep
    runoff_soil = calc_runoff_numba(W_adj, wmm, wm, b, pe)

    W_new, WU_new, WL_new, WD_new, evap = update_soil_smooth_et_numba(
        WU_adj, WL_adj, WD_adj, runoff_soil, runoff_pdd, ep, wum, wlm, wdm, ce, m_et)

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


def simulate_pdd_xaj_smooth_et(rain, pet, temp, params, initial_state=None):
    """PDD + XAJ-SmoothET 耦合模拟。22 参数 (6 PDD + 16 XAJ-SmoothET)。"""
    T = len(rain)
    wm = params['wum'] + params['wlm'] + params['wdm']
    wmm = wm * (1 + params['b']) / (1 - params['imp'])
    ms = params['sm'] * (1 + params['ex'])

    xaj_pars = tuple(np.array([np.float64(v)]) for v in (
        params['kc'], params['ki'], params['kg'],
        params['cs'], params['ci'], params['cg'],
        params['wum'], params['wlm'], params['wdm'],
        params['sm'], params['imp'], params['c'],
        params['b'], params['ex'], 1.0, wmm, ms,
        params['ce'], params['m_et'],
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
        state, _ = coupled_pdd_xaj_smooth_et_step_numba(
            state, temp_t, rain_t, snow_t, pet_t, pdd_pars, xaj_pars)
        q[t] = state[0, 8] + state[0, 9] + state[0, 10]

    return np.maximum(q, 0.0), state.copy()
