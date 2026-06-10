"""GR4J + PDD-noice 模型封装：模拟 + CMA-ES 率定。

- GR4J: 4 参 (x1 production, x2 exchange, x3 routing, x4 UH time base)
- PDD-noice 雪前端: 4 参 (pdd_factor_snow, refreeze_snow, temp_snow, temp_rain)
- 合计 8 参，三学派里最省。

率定**共享** XAJ 的标定核心 ``_cmaes_multi_restart`` (同 seed/init/loss/warmup)，
仅传 ``constraint_fn=None`` (GR4J 无 ki/kg 约束) → 与 XAJ/HBV 同一标定条件。
"""
from __future__ import annotations

import numpy as np

from .xaj_model import _cmaes_multi_restart
from .gr4j_core import (
    GR4J_PARAM_BOUNDS, GR4J_PARAM_NAMES,
    PDD_NOICE_PARAM_BOUNDS, PDD_NOICE_PARAM_NAMES,
    PDD_GR4J_PARAM_NAMES, STATE_DIM, STATE_NAMES,
    simulate_pdd_gr4j as _simulate_pdd_gr4j_core,
    simulate_gr4j as _simulate_gr4j_core,
)
from .gr4j_numba import simulate_pdd_gr4j_fast, _HAS_NUMBA

# 联合参数边界 (PDD-noice 在前，与 PDD_GR4J_PARAM_NAMES 同序)
PDD_GR4J_PARAM_BOUNDS = {**PDD_NOICE_PARAM_BOUNDS, **GR4J_PARAM_BOUNDS}

# Bounds presets (同 XAJ 的机制)。v1 = 默认。wide preset 待 iter3 饱和审计后填充。
GR4J_BOUNDS_PRESETS: dict[str, dict[str, tuple[float, float]]] = {
    "v1": {},
    # v2_wide: 应对 iter1/iter2 饱和审计 (independent review M2)。子集 39 中
    # x2 36% 贴 -5 下界 (失水支被截断)、x1 15% 贴 2500、x3 15% 贴 1000 → 放宽
    # 这三个有水文信号的库参。雪 4 参虽大面积贴界 (M1)，但在温暖流域是
    # dead parameters (不可辨识, 不影响 NSE) → 不放宽 (放了徒增搜索空间)。
    # x4 贴界不显著 + 放大受 NUH_MAX 限制 → 不动。
    "v2_wide": {
        "x1": (1.0, 4000.0),    # production store (was 2500) — 干旱大流域
        "x2": (-15.0, 5.0),     # groundwater exchange (was -5) — 放失水下界
        "x3": (1.0, 1500.0),    # routing store (was 1000)
    },
}


def resolve_gr4j_bounds(preset: str) -> dict:
    """返回 ``preset`` 的 8 参合并边界，保持 PDD_GR4J_PARAM_NAMES 顺序。"""
    if preset not in GR4J_BOUNDS_PRESETS:
        raise ValueError(f"Unknown GR4J bounds preset {preset!r}. "
                         f"Known: {sorted(GR4J_BOUNDS_PRESETS)}")
    merged = dict(PDD_GR4J_PARAM_BOUNDS)
    for name, rng in GR4J_BOUNDS_PRESETS[preset].items():
        if name not in merged:
            raise KeyError(f"Preset {preset!r} overrides unknown param {name!r}")
        merged[name] = tuple(rng)
    return merged


def simulate_pdd_gr4j(rain: np.ndarray, pet: np.ndarray, temp: np.ndarray,
                      params: dict, initial_state: np.ndarray | None = None
                      ) -> tuple[np.ndarray, np.ndarray]:
    """PDD-noice + GR4J 模拟。有 numba 时自动加速 (数值与 core 参考一致)。"""
    if _HAS_NUMBA:
        return simulate_pdd_gr4j_fast(rain, pet, temp, params, initial_state)
    return _simulate_pdd_gr4j_core(rain, pet, temp, params, initial_state)


def calibrate_pdd_gr4j(rain: np.ndarray, pet: np.ndarray, temp: np.ndarray,
                       obs: np.ndarray, n_trials: int = 5000, n_restarts: int = 3,
                       init_mean: float = 0.5, init_sigma: float = 0.3,
                       loss: str = 'nse', kge_weight: float = 0.5,
                       param_bounds: dict | None = None) -> dict:
    """CMA-ES 多重启率定 PDD+GR4J (8 参)。

    复用 ``_cmaes_multi_restart`` 全部 playbook 旋钮；``constraint_fn=None`` 因
    GR4J 没有 ki/kg。``param_bounds`` 可覆盖默认边界 (bounds-widening lever)，
    须保持 ``PDD_GR4J_PARAM_NAMES`` 的 8 参顺序。
    """
    all_bounds = param_bounds if param_bounds is not None else dict(PDD_GR4J_PARAM_BOUNDS)
    return _cmaes_multi_restart(
        lambda rpt_p: simulate_pdd_gr4j(rpt_p[0], rpt_p[1], rpt_p[2], rpt_p[3]),
        (rain, pet, temp), obs, PDD_GR4J_PARAM_NAMES, all_bounds,
        n_trials=n_trials, n_restarts=n_restarts,
        init_mean=init_mean, init_sigma=init_sigma,
        loss=loss, kge_weight=kge_weight,
        constraint_fn=None,
    )
