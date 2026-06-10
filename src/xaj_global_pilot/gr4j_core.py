"""GR4J (Perrin et al. 2003) 概念水文模型 — NumPy 参考实现。

4 参数:
    x1  production store capacity (mm)
    x2  groundwater exchange coefficient (mm)
    x3  routing store capacity (mm)
    x4  unit hydrograph time base (day)

雪前端: PDD (positive degree-day) 的 **noice** 子集 (CAMELS-US 无冰川，ice
分量恒 0)，4 参: pdd_factor_snow, refreeze_snow, temp_snow, temp_rain。雨雪分
离与融雪逻辑与 ``xaj_numba`` 中 PDD+XAJ 用的完全一致 → 雪前端在 GR4J/XAJ 间被
控制为同一个，对比干净。

本文件是**可读的标量参考实现 (ground truth)**，用于单元自检与对拍。生产/标定走
``gr4j_numba.py`` 的 njit 版 (数值与本文件一致)。单位全程 mm/day。

State 向量 (flat, 长度 = 5 + NUH1_MAX + NUH2_MAX):
    [snow, ice(=0), last_temp, S, R, StUH1[0..NUH1_MAX-1], StUH2[0..NUH2_MAX-1]]
其中 StUH1/StUH2 是单位线卷积队列 (StUH[0] = 今天输出)。
"""
from __future__ import annotations

import numpy as np

# ---------------------------------------------------------------------------
# 参数边界 (airGR / Perrin 2003 文献范围)
# ---------------------------------------------------------------------------
GR4J_PARAM_BOUNDS = {
    'x1': (1.0, 2500.0),   # production store capacity (mm)
    'x2': (-5.0, 5.0),     # groundwater exchange coefficient (mm)
    'x3': (1.0, 1000.0),   # routing store capacity (mm)
    'x4': (0.5, 10.0),     # unit hydrograph time base (day)
}
GR4J_PARAM_NAMES = list(GR4J_PARAM_BOUNDS.keys())

# PDD-noice 雪参 (从 PDD_PARAM_BOUNDS 取保留的 4 个，砍掉 ice 两参)
PDD_NOICE_PARAM_BOUNDS = {
    'pdd_factor_snow': (0.5, 10.0),   # mm/°C/day
    'refreeze_snow':   (0.0, 0.5),    # 重冻结比例
    'temp_snow':       (-3.0, 1.0),   # 全雪温度阈值 (°C)
    'temp_rain':       (0.5, 4.0),    # 全雨温度阈值 (°C)
}
PDD_NOICE_PARAM_NAMES = list(PDD_NOICE_PARAM_BOUNDS.keys())

# PDD+GR4J 联合参数 (雪在前，与 PDD+XAJ 的 PDD-first 约定一致)
PDD_GR4J_PARAM_NAMES = PDD_NOICE_PARAM_NAMES + GR4J_PARAM_NAMES  # 8 参

# UH 队列预分配上界。x4<=10 → ceil(x4)<=10, ceil(2*x4)<=20。预留更大以兼容
# 未来的 wide bounds (x4<=18 安全)。超出 ceil 的 ordinate 自然为 0，无害。
NUH1_MAX = 20
NUH2_MAX = 40

# state flat 布局
STATE_DIM = 5 + NUH1_MAX + NUH2_MAX  # snow,ice,last_temp,S,R + 两个 UH 队列
_IDX_SNOW, _IDX_ICE, _IDX_TEMP, _IDX_S, _IDX_R = 0, 1, 2, 3, 4
_IDX_UH1 = 5
_IDX_UH2 = 5 + NUH1_MAX

STATE_NAMES = (
    ['snow', 'ice', 'last_temp', 'S', 'R']
    + [f'uh1_{i}' for i in range(NUH1_MAX)]
    + [f'uh2_{i}' for i in range(NUH2_MAX)]
)


# ---------------------------------------------------------------------------
# 单位线 ordinates
# ---------------------------------------------------------------------------
def uh1_ordinates(x4: float, n_max: int = NUH1_MAX) -> np.ndarray:
    """UH1(j) = SH1(j) - SH1(j-1); SH1(t) = (t/x4)^2.5 (0<t<x4), 1 (t>=x4)."""
    out = np.zeros(n_max, dtype=np.float64)
    nuh1 = max(1, int(np.ceil(x4)))
    prev = 0.0
    for j in range(1, nuh1 + 1):
        tj = j / x4
        sh = tj ** 2.5 if tj < 1.0 else 1.0
        out[j - 1] = sh - prev
        prev = sh
    return out


def uh2_ordinates(x4: float, n_max: int = NUH2_MAX) -> np.ndarray:
    """UH2(j) = SH2(j) - SH2(j-1);
    SH2(t) = 0.5(t/x4)^2.5 (0<t<=x4); 1-0.5(2-t/x4)^2.5 (x4<t<2x4); 1 (t>=2x4)."""
    out = np.zeros(n_max, dtype=np.float64)
    nuh2 = max(1, int(np.ceil(2.0 * x4)))
    prev = 0.0
    for j in range(1, nuh2 + 1):
        tj = j / x4
        if tj <= 1.0:
            sh = 0.5 * tj ** 2.5
        elif tj < 2.0:
            sh = 1.0 - 0.5 * (2.0 - tj) ** 2.5
        else:
            sh = 1.0
        out[j - 1] = sh - prev
        prev = sh
    return out


# ---------------------------------------------------------------------------
# 单步: 雪前端 + GR4J
# ---------------------------------------------------------------------------
def _snow_noice_step(snow_depth, temp, prec, fsnow, rfsnow, temp_snow, temp_rain):
    """PDD-noice 单步 (标量)。返回 (new_snow_depth, liquid_input_mm)。"""
    snow_frac = (temp_rain - temp) / (temp_rain - temp_snow + 1e-12)
    snow_frac = min(1.0, max(0.0, snow_frac))
    snowfall = prec * snow_frac
    rainfall = prec - snowfall

    snow_depth = snow_depth + snowfall
    pdd = temp if temp > 0.0 else 0.0
    pot_melt = fsnow * pdd
    act_melt = min(snow_depth, pot_melt)
    refrozen = act_melt * rfsnow
    snow_depth = snow_depth - act_melt + refrozen
    if snow_depth < 0.0:
        snow_depth = 0.0
    liquid = act_melt - refrozen + rainfall
    return snow_depth, liquid


def _gr4j_step(S, R, stuh1, stuh2, uh1, uh2, nuh1, nuh2, P, E, x1, x2, x3):
    """GR4J 单步 (标量)。stuh1/stuh2 原地更新。返回 (S, R, Q)。"""
    # 1. 净雨 / 净蒸发 + production store
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

    # 2. percolation
    perc = S * (1.0 - (1.0 + (S / (2.25 * x1)) ** 4) ** (-0.25))
    S = S - perc

    # 3. routing 输入 + 90/10 分流
    Pr = perc + pr_excess
    prr = 0.9 * Pr
    prd = 0.1 * Pr

    # 4. UH 卷积推进 (StUH[0] = 今天输出)
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

    # 5. groundwater exchange
    F = x2 * (R / x3) ** 3.5

    # 6. routing store
    R = R + q9 + F
    if R < 0.0:
        R = 0.0
    qr = R * (1.0 - (1.0 + (R / x3) ** 4) ** (-0.25))
    R = R - qr

    # 7. direct flow
    qd = q1 + F
    if qd < 0.0:
        qd = 0.0

    return S, R, qr + qd


# ---------------------------------------------------------------------------
# 高层模拟
# ---------------------------------------------------------------------------
def _default_state(x1: float, x3: float) -> np.ndarray:
    st = np.zeros(STATE_DIM, dtype=np.float64)
    st[_IDX_S] = 0.5 * x1
    st[_IDX_R] = 0.5 * x3
    return st


def simulate_pdd_gr4j(rain: np.ndarray, pet: np.ndarray, temp: np.ndarray,
                      params: dict, initial_state: np.ndarray | None = None
                      ) -> tuple[np.ndarray, np.ndarray]:
    """PDD-noice + GR4J 耦合模拟 (NumPy 参考)。

    rain, pet: (T,) mm/day ; temp: (T,) °C
    params: dict, 含 PDD_GR4J_PARAM_NAMES 的 8 个键
    返回: (q (T,), final_state (STATE_DIM,))
    """
    x1, x2, x3, x4 = params['x1'], params['x2'], params['x3'], params['x4']
    fsnow = params['pdd_factor_snow']
    rfsnow = params['refreeze_snow']
    temp_snow = params['temp_snow']
    temp_rain = params['temp_rain']

    uh1 = uh1_ordinates(x4)
    uh2 = uh2_ordinates(x4)
    nuh1 = max(1, int(np.ceil(x4)))
    nuh2 = max(1, int(np.ceil(2.0 * x4)))

    st = (initial_state.copy().astype(np.float64)
          if initial_state is not None else _default_state(x1, x3))
    snow_depth = st[_IDX_SNOW]
    S = st[_IDX_S]
    R = st[_IDX_R]
    stuh1 = st[_IDX_UH1:_IDX_UH1 + NUH1_MAX].copy()
    stuh2 = st[_IDX_UH2:_IDX_UH2 + NUH2_MAX].copy()

    T = len(rain)
    q = np.zeros(T, dtype=np.float64)
    for t in range(T):
        snow_depth, P = _snow_noice_step(
            snow_depth, temp[t], rain[t], fsnow, rfsnow, temp_snow, temp_rain)
        S, R, qt = _gr4j_step(
            S, R, stuh1, stuh2, uh1, uh2, nuh1, nuh2, P, pet[t], x1, x2, x3)
        q[t] = qt

    out = np.zeros(STATE_DIM, dtype=np.float64)
    out[_IDX_SNOW] = snow_depth
    out[_IDX_TEMP] = temp[T - 1] if T > 0 else 0.0
    out[_IDX_S] = S
    out[_IDX_R] = R
    out[_IDX_UH1:_IDX_UH1 + NUH1_MAX] = stuh1
    out[_IDX_UH2:_IDX_UH2 + NUH2_MAX] = stuh2
    return np.maximum(q, 0.0), out


def simulate_gr4j(rain: np.ndarray, pet: np.ndarray, params: dict,
                  initial_state: np.ndarray | None = None
                  ) -> tuple[np.ndarray, np.ndarray]:
    """纯 GR4J (无雪前端, P=rain 直接入产流)。用于无雪流域对照/退化自检。"""
    temp = np.full(len(rain), 100.0)  # 恒高温 → snow_frac=0, 全为液态, 融雪=0
    p = dict(params)
    p.setdefault('pdd_factor_snow', 1.0)
    p.setdefault('refreeze_snow', 0.0)
    p.setdefault('temp_snow', -3.0)
    p.setdefault('temp_rain', 0.5)
    return simulate_pdd_gr4j(rain, pet, temp, p, initial_state)
