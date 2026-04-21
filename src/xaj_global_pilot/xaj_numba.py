"""Numba 加速的 XAJ + PDD 核心计算函数。

移植自 forecast_system_lite/src/kernels/semi_distributed/core/hydromod_numba.py
当 numba 不可用时自动退化为纯 Python（慢但功能一致）。

所有函数单位统一为 mm（无米/毫米转换），与 forecast_system_lite 生产版本一致。
PDD 接收预分离的 rain/snow（mm），输出 runoff（mm）。
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


# ===================================================================
# PDD 融雪 (V1: 经典双层 snow+ice)
# ===================================================================

@njit(cache=True, fastmath=True)
def pdd_step_numba(
    state: np.ndarray,
    temp: np.ndarray,
    rain: np.ndarray,
    snow: np.ndarray,
    pdd_factor_snow: np.ndarray,
    pdd_factor_ice: np.ndarray,
    refreeze_snow: np.ndarray,
    refreeze_ice: np.ndarray,
) -> Tuple[np.ndarray, np.ndarray]:
    """PDD 单步 (N 并行)。输入输出均为 mm。

    state: (N, 3) [snow_depth_mm, ice_depth_mm, last_temp_C]
    返回: (new_state, runoff_mm)
    """
    snow_depth = state[:, 0].copy()
    ice_depth = state[:, 1].copy()

    snow_depth += snow
    pdd = np.maximum(temp, 0.0)

    tiny = np.float64(1e-12)
    fsnow = pdd_factor_snow
    fice = pdd_factor_ice

    pot_snow_melt = fsnow * pdd
    act_snow_melt = np.minimum(snow_depth, pot_snow_melt)

    remaining_e = pot_snow_melt - act_snow_melt
    ice_melt = np.where(fsnow > tiny, remaining_e * (fice / fsnow), fice * pdd)
    act_ice_melt = np.minimum(ice_depth, ice_melt)

    ref_snow = act_snow_melt * refreeze_snow
    ref_ice = act_ice_melt * refreeze_ice

    snow_depth = snow_depth - act_snow_melt + ref_snow
    ice_depth = ice_depth - act_ice_melt + ref_ice

    runoff = act_snow_melt + act_ice_melt - ref_snow - ref_ice + rain

    new_state = np.empty_like(state)
    new_state[:, 0] = np.maximum(snow_depth, 0.0)
    new_state[:, 1] = np.maximum(ice_depth, 0.0)
    new_state[:, 2] = temp

    return new_state, runoff


# ===================================================================
# XAJ 核心函数
# ===================================================================

@njit(cache=True, fastmath=True)
def update_q_numba(qs, qi, qg, rs, ri, rg, cs, ci_, cg_, uf):
    qs_new = cs * qs + (1 - cs) * rs * uf
    qi_new = ci_ * qi + (1 - ci_) * ri * uf
    qg_new = cg_ * qg + (1 - cg_) * rg * uf
    return qs_new, qi_new, qg_new


@njit(fastmath=True, cache=True)
def redistribute_soil_water_numba(w, wu, wl, wd, wm, wum, wlm, wdm):
    w = np.clip(w, 0.0, wm)
    extra = w - (wu + wl + wd)

    for i in range(w.size):
        if extra[i] > 1e-4:
            take = min(extra[i], wum[i] - wu[i]); wu[i] += take; extra[i] -= take
            take = min(extra[i], wlm[i] - wl[i]); wl[i] += take; extra[i] -= take
            take = min(extra[i], wdm[i] - wd[i]); wd[i] += take; extra[i] -= take
        elif extra[i] < -1e-4:
            take = min(-extra[i], wu[i]); wu[i] -= take; extra[i] += take
            take = min(-extra[i], wl[i]); wl[i] -= take; extra[i] += take
            take = min(-extra[i], wd[i]); wd[i] -= take; extra[i] += take

    wu = np.clip(wu, 0.0, wum)
    wl = np.clip(wl, 0.0, wlm)
    wd = np.clip(wd, 0.0, wdm)
    return w, wu, wl, wd


@njit(fastmath=True, cache=True)
def calc_runoff_numba(w, wmm, wm, b, pe):
    wm_safe = np.maximum(wm, 1e-12)
    frac = np.maximum(0.0, np.minimum(1.0, 1 - w / wm_safe))
    w_temp = wmm * (1 - np.power(frac, 1.0 / (1.0 + b)))
    tmp = w_temp + pe
    cond = tmp <= wmm
    out = np.where(
        (pe > 0) & cond,
        pe + w - wm + wm * np.power(1 - tmp / wmm, 1 + b),
        np.where((pe > 0) & (~cond), pe + w - wm, 0.0)
    )
    return out


@njit(cache=True, fastmath=True)
def update_soil_layers_numba(
    wu, wl, wd, runoff, rain, ep, wum, wlm, wdm, cpar
):
    """三层蒸散发 + 土壤水更新。返回 (w, wu, wl, wd, evap)。"""
    pe = rain - ep
    water_extra = np.maximum(pe - runoff, 0.0)

    eu = np.zeros_like(pe)
    el = np.zeros_like(pe)
    ed = np.zeros_like(pe)

    new_wu = wu.copy()
    new_wl = wl.copy()
    new_wd = wd.copy()

    # pe > 0
    mask_pos = pe > 0.0
    if mask_pos.any():
        idx = np.where(mask_pos)
        eu[idx] = ep[idx]

        wu_plus = new_wu[idx] + water_extra[idx]
        over1 = wu_plus > wum[idx]
        new_wu[idx] = np.where(over1, wum[idx], wu_plus)
        water_extra1 = np.where(over1, wu_plus - wum[idx], 0.0)

        wl_plus = new_wl[idx] + water_extra1
        over2 = wl_plus > wlm[idx]
        new_wl[idx] = np.where(over2, wlm[idx], wl_plus)
        water_extra2 = np.where(over2, wl_plus - wlm[idx], 0.0)

        wd_plus = new_wd[idx] + water_extra2
        over3 = wd_plus > wdm[idx]
        new_wd[idx] = np.where(over3, wdm[idx], wd_plus)

    # pe <= 0
    mask_neg = pe <= 0.0
    if mask_neg.any():
        idx = np.where(mask_neg)[0]
        cond_A = (new_wu[idx] + rain[idx]) > ep[idx]

        if cond_A.any():
            ia = idx[cond_A]
            eu[ia] = ep[ia]
            new_wu[ia] += pe[ia]

        if (~cond_A).any():
            ib = idx[~cond_A]
            eu[ib] = new_wu[ib] + rain[ib]
            remainder = ep[ib] - eu[ib]
            new_wu[ib] = 0.0

            cond1 = new_wl[ib] >= cpar[ib] * wlm[ib]
            ia2 = ib[cond1]
            if ia2.size:
                el_a = np.abs(remainder[cond1] * new_wl[ia2] / wlm[ia2])
                new_wl[ia2] -= el_a
                el[ia2] = el_a

            cond2 = ~cond1 & (new_wl[ib] >= cpar[ib] * np.abs(remainder))
            ib2 = ib[cond2]
            if ib2.size:
                el_b = cpar[ib2] * np.abs(remainder[cond2])
                new_wl[ib2] -= el_b
                el[ib2] = el_b

            ic2 = ib[~cond1 & ~cond2]
            if ic2.size:
                el[ic2] = new_wl[ic2]
                new_wl[ic2] = 0.0
                ed_c = np.abs(cpar[ic2] * remainder[~cond1 & ~cond2] - el[ic2])
                new_wd[ic2] -= ed_c
                ed[ic2] = ed_c

    new_wu = np.clip(new_wu, 0.0, wum)
    new_wl = np.clip(new_wl, 0.0, wlm)
    new_wd = np.clip(new_wd, 0.0, wdm)

    w_total = new_wu + new_wl + new_wd
    evap = eu + el + ed
    return w_total, new_wu, new_wl, new_wd, evap


@njit(cache=True, fastmath=True)
def free_water_numba(s, runoff, pe, ki, kg, ms, sm, ex):
    """自由水蓄水库 — 三水源划分。返回 (s, RS, RI, RG, fr)。"""
    zero = 0.0
    one = 1.0
    tiny = 1e-12

    # 与 forecast_system_lite 生产版本一致：无条件削减
    s_new = np.minimum(sm, s) * (one - ki - kg)

    sm_safe = np.maximum(sm, tiny)
    frac = np.clip(one - s_new / sm_safe, zero, one)
    s_temp = ms * (one - np.power(frac, one / (one + ex)))

    fr = np.zeros_like(pe)
    mask = (runoff > zero) & (pe > tiny)
    fr[mask] = np.minimum(one, runoff[mask] / pe[mask])

    RS = np.zeros_like(pe)
    cond1 = (runoff > zero) & ((pe + s_temp) < ms)
    RS[cond1] = fr[cond1] * (
        pe[cond1] + s_new[cond1] - sm[cond1] +
        sm[cond1] * np.power(one - (pe[cond1] + s_temp[cond1]) / ms[cond1], one + ex[cond1])
    )
    cond2 = (runoff > zero) & (~cond1)
    RS[cond2] = fr[cond2] * (pe[cond2] + s_new[cond2] - sm[cond2])

    ratio_rs = np.zeros_like(RS)
    nz = fr > tiny
    ratio_rs[nz] = RS[nz] / fr[nz]
    s_new = np.where(runoff > zero,
                     np.clip(s_new + pe - ratio_rs, zero, sm),
                     np.minimum(sm, s_new))

    RI = ki * s_new * fr
    RG = kg * s_new * fr
    return s_new, RS, RI, RG, fr


# ===================================================================
# 耦合步进函数
# ===================================================================

@njit(cache=True, fastmath=True)
def coupled_pdd_xaj_step_numba(
    joint_state,
    temp, rain, snow, pet,
    pdd_pars,
    xaj_pars
):
    """PDD+XAJ 耦合单步 (numba)。

    joint_state: (N, 11)  [snow_depth, ice_depth, last_temp, W, WU, WL, WD, S, QS, QI, QG]
    pdd_pars: tuple(4) — (fsnow, fice, rfsnow, rfice)，均为 (N,) 数组
    xaj_pars: tuple(17) — (kc, ki, kg, cs, ci, cg, wum, wlm, wdm, sm, imp, c, b, ex, uf, wmm, ms)
    返回: (new_state, runoff_pdd)
    """
    fsnow, fice, rfsnow, rfice = pdd_pars
    kc, ki, kg, cs, ci_, cg_, wum, wlm, wdm, sm, imp, cpar, b, ex, uf, wmm, ms = xaj_pars

    pdd_state = joint_state[:, :3]
    W = joint_state[:, 3]
    WU = joint_state[:, 4]
    WL = joint_state[:, 5]
    WD = joint_state[:, 6]
    S = joint_state[:, 7]
    QS = joint_state[:, 8]
    QI = joint_state[:, 9]
    QG = joint_state[:, 10]

    new_pdd_state, runoff_pdd = pdd_step_numba(
        pdd_state, temp, rain, snow, fsnow, fice, rfsnow, rfice)

    wm = wum + wlm + wdm
    W_adj, WU_adj, WL_adj, WD_adj = redistribute_soil_water_numba(
        W, WU, WL, WD, wm, wum, wlm, wdm)

    ep = pet * kc
    pe = runoff_pdd - ep

    runoff_soil = calc_runoff_numba(W_adj, wmm, wm, b, pe)

    W_new, WU_new, WL_new, WD_new, evap = update_soil_layers_numba(
        WU_adj, WL_adj, WD_adj, runoff_soil, runoff_pdd, ep, wum, wlm, wdm, cpar)

    S_new, RS, RI, RG, fr = free_water_numba(
        S, runoff_soil, pe, ki, kg, ms, sm, ex)

    QS_new, QI_new, QG_new = update_q_numba(
        QS, QI, QG, RS, RI, RG, cs, ci_, cg_, uf)

    new_state = np.empty_like(joint_state)
    new_state[:, 0] = new_pdd_state[:, 0]
    new_state[:, 1] = new_pdd_state[:, 1]
    new_state[:, 2] = new_pdd_state[:, 2]
    new_state[:, 3] = W_new
    new_state[:, 4] = WU_new
    new_state[:, 5] = WL_new
    new_state[:, 6] = WD_new
    new_state[:, 7] = S_new
    new_state[:, 8] = QS_new
    new_state[:, 9] = QI_new
    new_state[:, 10] = QG_new

    return new_state, runoff_pdd


# ===================================================================
# 纯 XAJ 步进 (无 PDD)
# ===================================================================

@njit(cache=True, fastmath=True)
def xaj_step_numba(
    state,
    rain, pet,
    xaj_pars
):
    """纯 XAJ 单步 (numba)。

    state: (N, 8) [W, WU, WL, WD, S, QS, QI, QG]
    xaj_pars: tuple(17)
    返回: new_state (N, 8)
    """
    kc, ki, kg, cs, ci_, cg_, wum, wlm, wdm, sm, imp, cpar, b, ex, uf, wmm, ms = xaj_pars

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

    # IMP 已通过 wmm = wm*(1+b)/(1-imp) 融入 B 曲线，无需二次拆分
    runoff_soil = calc_runoff_numba(W_adj, wmm, wm, b, pe)

    W_new, WU_new, WL_new, WD_new, evap = update_soil_layers_numba(
        WU_adj, WL_adj, WD_adj, runoff_soil, rain, ep, wum, wlm, wdm, cpar)

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
# 高层模拟函数（时间循环 + 雨雪分离）
# ===================================================================

def simulate_xaj_fast(rain, pet, params, initial_state=None):
    """Numba 加速的纯 XAJ 模拟。

    rain, pet: (T,) mm/timestep
    params: dict with 14 XAJ parameters
    返回: (q, final_state)  q: (T,) mm/timestep, final_state: (1, 8)
    """
    T = len(rain)
    wm = params['wum'] + params['wlm'] + params['wdm']
    wmm = wm * (1 + params['b']) / (1 - params['imp'])
    ms = params['sm'] * (1 + params['ex'])

    # xaj_pars: tuple(17)
    xaj_pars = (
        np.float64(params['kc']), np.float64(params['ki']), np.float64(params['kg']),
        np.float64(params['cs']), np.float64(params['ci']), np.float64(params['cg']),
        np.float64(params['wum']), np.float64(params['wlm']), np.float64(params['wdm']),
        np.float64(params['sm']), np.float64(params['imp']), np.float64(params['c']),
        np.float64(params['b']), np.float64(params['ex']), np.float64(1.0),
        np.float64(wmm), np.float64(ms),
    )

    if initial_state is not None:
        state = initial_state.copy().astype(np.float64)
    else:
        state = np.array([[
            params['wum'] * 0.5 + params['wlm'] * 0.5 + params['wdm'] * 0.5,
            params['wum'] * 0.5, params['wlm'] * 0.5, params['wdm'] * 0.5,
            params['sm'] * 0.5, 0.0, 0.0, 0.0,
        ]])

    # 向量化 xaj_pars 为 (1,) 数组
    xp = tuple(np.array([v]) for v in xaj_pars)

    q = np.zeros(T)
    for t in range(T):
        r_t = np.array([rain[t]])
        p_t = np.array([pet[t]])
        state = xaj_step_numba(state, r_t, p_t, xp)
        q[t] = state[0, 5] + state[0, 6] + state[0, 7]

    return np.maximum(q, 0.0), state.copy()


def simulate_pdd_xaj_fast(rain, pet, temp, params, initial_state=None):
    """Numba 加速的 PDD+XAJ 耦合模拟。

    rain, pet, temp: (T,) mm/timestep, mm/timestep, °C
    params: dict with 20 parameters (6 PDD + 14 XAJ)
    返回: (q, final_state)  q: (T,) mm/timestep, final_state: (1, 11)
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
    ))

    pdd_pars = tuple(np.array([np.float64(params[k])]) for k in (
        'pdd_factor_snow', 'pdd_factor_ice', 'refreeze_snow', 'refreeze_ice'))

    # 雨雪分离参数
    temp_snow = params.get('temp_snow', 0.0)
    temp_rain = params.get('temp_rain', 2.0)

    if initial_state is not None:
        state = initial_state.copy().astype(np.float64)
    else:
        state = np.array([[
            0.0, 0.0, 0.0,  # PDD: snow, ice, last_temp
            params['wum'] * 0.5 + params['wlm'] * 0.5 + params['wdm'] * 0.5,
            params['wum'] * 0.5, params['wlm'] * 0.5, params['wdm'] * 0.5,
            params['sm'] * 0.5, 0.0, 0.0, 0.0,
        ]])

    q = np.zeros(T)
    for t in range(T):
        t_val = temp[t]
        # 雨雪分离
        snow_frac = np.clip((temp_rain - t_val) / (temp_rain - temp_snow + 1e-12), 0.0, 1.0)
        snow_t = np.array([rain[t] * snow_frac])
        rain_t = np.array([rain[t] * (1.0 - snow_frac)])
        pet_t = np.array([pet[t]])
        temp_t = np.array([t_val])

        state, _ = coupled_pdd_xaj_step_numba(
            state, temp_t, rain_t, snow_t, pet_t, pdd_pars, xaj_pars)
        q[t] = state[0, 8] + state[0, 9] + state[0, 10]

    return np.maximum(q, 0.0), state.copy()
