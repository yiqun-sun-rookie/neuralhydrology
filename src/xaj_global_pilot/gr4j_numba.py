"""Numba 加速的 GR4J + PDD-noice 核心计算。

数值与 ``gr4j_core.py`` 的标量参考实现一致 (单元自检对拍 |Δ|<1e-9)。当 numba
不可用时自动退化为纯 Python (慢但功能一致)。单位全程 mm/day。
"""
from __future__ import annotations

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

from .gr4j_core import (
    NUH1_MAX, NUH2_MAX, STATE_DIM,
    _IDX_SNOW, _IDX_TEMP, _IDX_S, _IDX_R, _IDX_UH1, _IDX_UH2,
)


@njit(cache=True, fastmath=True)
def _sim_pdd_gr4j_njit(rain, pet, temp,
                       fsnow, rfsnow, temp_snow, temp_rain,
                       x1, x2, x3, x4,
                       snow0, S0, R0, stuh1_0, stuh2_0):
    T = rain.size

    # --- UH ordinates ---
    nuh1 = int(np.ceil(x4))
    if nuh1 < 1:
        nuh1 = 1
    nuh2 = int(np.ceil(2.0 * x4))
    if nuh2 < 1:
        nuh2 = 1

    uh1 = np.zeros(NUH1_MAX)
    prev = 0.0
    for j in range(1, nuh1 + 1):
        tj = j / x4
        sh = tj ** 2.5 if tj < 1.0 else 1.0
        uh1[j - 1] = sh - prev
        prev = sh

    uh2 = np.zeros(NUH2_MAX)
    prev = 0.0
    for j in range(1, nuh2 + 1):
        tj = j / x4
        if tj <= 1.0:
            sh = 0.5 * tj ** 2.5
        elif tj < 2.0:
            sh = 1.0 - 0.5 * (2.0 - tj) ** 2.5
        else:
            sh = 1.0
        uh2[j - 1] = sh - prev
        prev = sh

    # --- state ---
    snow_depth = snow0
    S = S0
    R = R0
    stuh1 = stuh1_0.copy()
    stuh2 = stuh2_0.copy()

    q = np.zeros(T)
    last_temp = 0.0
    for t in range(T):
        tv = temp[t]
        last_temp = tv

        # 雪前端 (PDD-noice)
        snow_frac = (temp_rain - tv) / (temp_rain - temp_snow + 1e-12)
        if snow_frac < 0.0:
            snow_frac = 0.0
        elif snow_frac > 1.0:
            snow_frac = 1.0
        snowfall = rain[t] * snow_frac
        rainfall = rain[t] - snowfall

        snow_depth += snowfall
        pdd = tv if tv > 0.0 else 0.0
        pot_melt = fsnow * pdd
        act_melt = snow_depth if snow_depth < pot_melt else pot_melt
        refrozen = act_melt * rfsnow
        snow_depth = snow_depth - act_melt + refrozen
        if snow_depth < 0.0:
            snow_depth = 0.0
        P = act_melt - refrozen + rainfall

        E = pet[t]

        # GR4J production store
        if P >= E:
            Pn = P - E
            sr = S / x1
            tws = np.tanh(Pn / x1)
            Ps = x1 * (1.0 - sr * sr) * tws / (1.0 + sr * tws)
            S = S + Ps
            pr_excess = Pn - Ps
        else:
            En = E - P
            sr = S / x1
            tws = np.tanh(En / x1)
            Es = S * (2.0 - sr) * tws / (1.0 + (1.0 - sr) * tws)
            S = S - Es
            pr_excess = 0.0

        # percolation
        perc = S * (1.0 - (1.0 + (S / (2.25 * x1)) ** 4) ** (-0.25))
        S = S - perc

        # routing 输入 + 90/10 分流
        Pr = perc + pr_excess
        prr = 0.9 * Pr
        prd = 0.1 * Pr

        # UH 卷积推进
        for k in range(nuh1):
            stuh1[k] += uh1[k] * prr
        q9 = stuh1[0]
        for k in range(nuh1 - 1):
            stuh1[k] = stuh1[k + 1]
        stuh1[nuh1 - 1] = 0.0

        for k in range(nuh2):
            stuh2[k] += uh2[k] * prd
        q1 = stuh2[0]
        for k in range(nuh2 - 1):
            stuh2[k] = stuh2[k + 1]
        stuh2[nuh2 - 1] = 0.0

        # groundwater exchange + routing store
        F = x2 * (R / x3) ** 3.5
        R = R + q9 + F
        if R < 0.0:
            R = 0.0
        qr = R * (1.0 - (1.0 + (R / x3) ** 4) ** (-0.25))
        R = R - qr

        qd = q1 + F
        if qd < 0.0:
            qd = 0.0

        qt = qr + qd
        q[t] = qt if qt > 0.0 else 0.0

    return q, snow_depth, last_temp, S, R, stuh1, stuh2


def simulate_pdd_gr4j_fast(rain, pet, temp, params, initial_state=None):
    """njit 加速的 PDD-noice + GR4J 模拟。返回 (q (T,), final_state (STATE_DIM,))."""
    x1 = float(params['x1']); x2 = float(params['x2'])
    x3 = float(params['x3']); x4 = float(params['x4'])
    fsnow = float(params['pdd_factor_snow'])
    rfsnow = float(params['refreeze_snow'])
    temp_snow = float(params['temp_snow'])
    temp_rain = float(params['temp_rain'])

    if initial_state is not None:
        st = np.asarray(initial_state, dtype=np.float64).reshape(-1)
        snow0 = st[_IDX_SNOW]; S0 = st[_IDX_S]; R0 = st[_IDX_R]
        stuh1_0 = st[_IDX_UH1:_IDX_UH1 + NUH1_MAX].copy()
        stuh2_0 = st[_IDX_UH2:_IDX_UH2 + NUH2_MAX].copy()
    else:
        snow0 = 0.0; S0 = 0.5 * x1; R0 = 0.5 * x3
        stuh1_0 = np.zeros(NUH1_MAX); stuh2_0 = np.zeros(NUH2_MAX)

    rain = np.ascontiguousarray(rain, dtype=np.float64)
    pet = np.ascontiguousarray(pet, dtype=np.float64)
    temp = np.ascontiguousarray(temp, dtype=np.float64)

    q, snow_f, temp_f, S_f, R_f, stuh1_f, stuh2_f = _sim_pdd_gr4j_njit(
        rain, pet, temp, fsnow, rfsnow, temp_snow, temp_rain,
        x1, x2, x3, x4, snow0, S0, R0, stuh1_0, stuh2_0)

    out = np.zeros(STATE_DIM, dtype=np.float64)
    out[_IDX_SNOW] = snow_f
    out[_IDX_TEMP] = temp_f
    out[_IDX_S] = S_f
    out[_IDX_R] = R_f
    out[_IDX_UH1:_IDX_UH1 + NUH1_MAX] = stuh1_f
    out[_IDX_UH2:_IDX_UH2 + NUH2_MAX] = stuh2_f
    return np.maximum(q, 0.0), out
