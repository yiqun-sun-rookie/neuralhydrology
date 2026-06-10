"""经典新安江模型封装：模拟 + CMA-ES 率定。

- XAJ: 14 参数，三层蒸发 + B 曲线蓄满产流 + 三水源划分 + 三段汇流
- PDD+XAJ: 20 参数 (6 PDD + 14 XAJ)，融雪 → 产流耦合
"""
import numpy as np
import pandas as pd
import cma

from .xaj_core import xaj_step_vec
from .pdd_core import pdd_step

try:
    from .xaj_numba import simulate_xaj_fast, simulate_pdd_xaj_fast, _HAS_NUMBA
except Exception:
    _HAS_NUMBA = False

from .xaj_numba_smooth_et import simulate_xaj_smooth_et, simulate_pdd_xaj_smooth_et
from .xaj_numba_power_runoff import simulate_xaj_power_runoff, simulate_pdd_xaj_power_runoff

# ---------------------------------------------------------------------------
# 参数边界（经典新安江标准范围）
# ---------------------------------------------------------------------------
PARAM_BOUNDS = {
    'kc':  (0.3,  1.8),    # 蒸散发折算系数（放宽，全球 PET 差异大）
    'b':   (0.05, 4.0),    # 蓄水容量曲线指数（放宽上界）
    'wum': (2.0,  120.0),  # 上层蓄水容量 (mm)
    'wlm': (5.0,  200.0),  # 中层蓄水容量 (mm)
    'wdm': (2.0,  150.0),  # 深层蓄水容量 (mm)（CAMELS 深根植被需要更大）
    'sm':  (2.0,  120.0),  # 自由水蓄水容量 (mm)
    'imp': (0.001, 0.35),  # 不透水面积比例（放宽）
    'c':   (0.01, 0.35),   # 深层蒸散发系数
    'ex':  (0.1,  4.0),    # 自由水蓄水曲线指数（放宽）
    'ki':  (0.01, 0.55),   # 壤中流出流系数
    'kg':  (0.01, 0.55),   # 地下径流出流系数
    'cs':  (0.1,  0.9),    # 地表径流消退系数
    'ci':  (0.3,  0.95),   # 壤中流消退系数
    'cg':  (0.5,  0.998),  # 地下径流消退系数
}

PARAM_NAMES = list(PARAM_BOUNDS.keys())

# PDD 融雪参数边界
PDD_PARAM_BOUNDS = {
    'pdd_factor_snow': (0.5, 10.0),   # mm/°C/day
    'pdd_factor_ice':  (1.0, 15.0),   # mm/°C/day
    'refreeze_snow':   (0.0, 0.5),    # 重冻结比例
    'refreeze_ice':    (0.0, 0.5),    # 重冻结比例
    'temp_snow':       (-3.0, 1.0),   # 全雪温度阈值 (°C)
    'temp_rain':       (0.5, 4.0),    # 全雨温度阈值 (°C)
}

PDD_PARAM_NAMES = list(PDD_PARAM_BOUNDS.keys())

# PDD+XAJ 联合参数
PDD_XAJ_PARAM_NAMES = PDD_PARAM_NAMES + PARAM_NAMES

WARMUP_DAYS = 365


# ---------------------------------------------------------------------------
# 模拟
# ---------------------------------------------------------------------------

def simulate_xaj(rain: np.ndarray, pet: np.ndarray, params: dict,
                 initial_state: np.ndarray | None = None) -> tuple[np.ndarray, np.ndarray]:
    """运行新安江模型。有 numba 时自动加速。"""
    if _HAS_NUMBA:
        return simulate_xaj_fast(rain, pet, params, initial_state)
    T = len(rain)

    # 衍生参数
    wm = params['wum'] + params['wlm'] + params['wdm']
    wmm = wm * (1 + params['b']) / (1 - params['imp'])
    ms = params['sm'] * (1 + params['ex'])

    # 构建参数字典 (shape (1,) 数组)
    pd_dict = {k: np.array([v]) for k, v in params.items()}
    pd_dict['wm'] = np.array([wm])
    pd_dict['wmm'] = np.array([wmm])
    pd_dict['ms'] = np.array([ms])
    pd_dict['uf'] = np.array([1.0])  # mm/timestep 单位，无需转换

    # 初始状态
    if initial_state is not None:
        state = initial_state.copy()
    else:
        state = np.array([[
            params['wum'] * 0.5 + params['wlm'] * 0.5 + params['wdm'] * 0.5,
            params['wum'] * 0.5,
            params['wlm'] * 0.5,
            params['wdm'] * 0.5,
            params['sm'] * 0.5,
            0.0, 0.0, 0.0,
        ]])

    q = np.zeros(T)
    for t in range(T):
        r_t = np.array([rain[t]])
        p_t = np.array([pet[t]])
        state = xaj_step_vec(state, r_t, p_t, pd_dict)
        q[t] = state[0, 5] + state[0, 6] + state[0, 7]  # qs + qi + qg

    return np.maximum(q, 0.0), state.copy()


# ---------------------------------------------------------------------------
# 率定
# ---------------------------------------------------------------------------

def calibrate_xaj(rain: np.ndarray, pet: np.ndarray, obs: np.ndarray,
                  n_trials: int = 2000, n_restarts: int = 3) -> dict:
    """CMA-ES 多重启全局优化率定。

    Parameters
    ----------
    n_trials : 每次重启的最大评估次数
    n_restarts : 重启次数（不同 seed），取最优
    """
    return _cmaes_multi_restart(
        lambda rain_pet_p: simulate_xaj(rain_pet_p[0], rain_pet_p[1], rain_pet_p[2]),
        (rain, pet), obs, PARAM_NAMES, PARAM_BOUNDS,
        n_trials=n_trials, n_restarts=n_restarts,
    )


# ---------------------------------------------------------------------------
# 辅助函数
# ---------------------------------------------------------------------------

def _enforce_ki_kg(params: dict) -> None:
    """约束 ki + kg <= 0.7。"""
    total = params['ki'] + params['kg']
    if total > 0.7:
        scale = 0.7 / total
        params['ki'] *= scale
        params['kg'] *= scale


def _nse(obs: np.ndarray, sim: np.ndarray) -> float:
    mask = np.isfinite(obs) & np.isfinite(sim)
    if mask.sum() < 10:
        return float('-inf')
    o = obs[mask]
    s = sim[mask]
    denom = float(((o - o.mean()) ** 2).sum())
    if denom < 1e-12:
        return float('-inf')
    return 1.0 - float(((o - s) ** 2).sum()) / denom


def _kge(obs: np.ndarray, sim: np.ndarray) -> float:
    """Kling-Gupta efficiency (same formulation as scl_hydro HBV-lite calibrator)."""
    mask = np.isfinite(obs) & np.isfinite(sim)
    if mask.sum() < 10:
        return float('-inf')
    o = obs[mask]
    s = sim[mask]
    o_mean, s_mean = o.mean(), s.mean()
    o_std, s_std = o.std(), s.std()
    if o_std == 0 or o_mean == 0:
        return float('-inf')
    r_num = float(((o - o_mean) * (s - s_mean)).sum())
    r_den = float(np.sqrt(((o - o_mean) ** 2).sum() * ((s - s_mean) ** 2).sum()))
    if r_den == 0:
        return float('-inf')
    r = r_num / r_den
    alpha = s_std / o_std
    beta = s_mean / o_mean
    return 1.0 - float(np.sqrt((r - 1) ** 2 + (alpha - 1) ** 2 + (beta - 1) ** 2))


# ===========================================================================
# PDD + XAJ 耦合模型
# ===========================================================================

def simulate_pdd_xaj(rain: np.ndarray, pet: np.ndarray, temp: np.ndarray,
                     params: dict, initial_state: np.ndarray | None = None
                     ) -> tuple[np.ndarray, np.ndarray]:
    """运行 PDD+XAJ 耦合模型。有 numba 时自动加速。"""
    if _HAS_NUMBA:
        return simulate_pdd_xaj_fast(rain, pet, temp, params, initial_state)
    T = len(rain)

    # XAJ 衍生参数
    wm = params['wum'] + params['wlm'] + params['wdm']
    wmm = wm * (1 + params['b']) / (1 - params['imp'])
    ms = params['sm'] * (1 + params['ex'])

    xaj_pd = {k: np.array([params[k]]) for k in PARAM_NAMES}
    xaj_pd['wm'] = np.array([wm])
    xaj_pd['wmm'] = np.array([wmm])
    xaj_pd['ms'] = np.array([ms])
    xaj_pd['uf'] = np.array([1.0])

    pdd_pd = {k: np.array([params[k]]) for k in PDD_PARAM_NAMES}

    # 初始状态: [pdd(3) | xaj(8)]
    if initial_state is not None:
        state = initial_state.copy()
    else:
        state = np.array([[
            0.0, 0.0, 0.0,  # pdd: snow_depth, ice_depth, last_temp
            params['wum'] * 0.5 + params['wlm'] * 0.5 + params['wdm'] * 0.5,
            params['wum'] * 0.5,
            params['wlm'] * 0.5,
            params['wdm'] * 0.5,
            params['sm'] * 0.5,
            0.0, 0.0, 0.0,
        ]])

    q = np.zeros(T)
    for t in range(T):
        pdd_state = state[:, :3]
        xaj_state = state[:, 3:]

        # PDD: 融雪产流 (输出单位: 米)
        new_pdd, pdd_runoff_m = pdd_step(
            pdd_state, np.array([temp[t]]), np.array([rain[t]]), pdd_pd)

        # PDD runoff (m → mm) 作为 XAJ 的降雨输入
        xaj_rain = pdd_runoff_m * 1000.0

        # XAJ: 产流 + 汇流
        new_xaj = xaj_step_vec(xaj_state, xaj_rain, np.array([pet[t]]), xaj_pd)

        state = np.hstack([new_pdd, new_xaj])
        q[t] = new_xaj[0, 5] + new_xaj[0, 6] + new_xaj[0, 7]

    return np.maximum(q, 0.0), state.copy()


# ---------------------------------------------------------------------------
# 消融实验：XAJ + HBV 式平滑蒸发
# ---------------------------------------------------------------------------

SMOOTH_ET_PARAM_BOUNDS = {
    **PARAM_BOUNDS,
    'ce':   (0.3, 1.5),    # 蒸发效率系数
    'm_et': (0.001, 0.5),  # 蒸发非线性指数
}

SMOOTH_ET_PARAM_NAMES = PARAM_NAMES + ['ce', 'm_et']


def calibrate_xaj_smooth_et(rain: np.ndarray, pet: np.ndarray, obs: np.ndarray,
                             n_trials: int = 2000, n_restarts: int = 3) -> dict:
    """CMA-ES 多重启率定 XAJ + HBV式平滑蒸发 (16 参数)。"""
    return _cmaes_multi_restart(
        lambda rain_pet_p: simulate_xaj_smooth_et(rain_pet_p[0], rain_pet_p[1], rain_pet_p[2]),
        (rain, pet), obs, SMOOTH_ET_PARAM_NAMES, SMOOTH_ET_PARAM_BOUNDS,
        n_trials=n_trials, n_restarts=n_restarts,
    )


# ---------------------------------------------------------------------------
# 消融实验 2：XAJ + HBV 式幂律产流
# ---------------------------------------------------------------------------

POWER_RUNOFF_PARAM_BOUNDS = {
    'kc':  (0.3,  1.8),
    'wum': (2.0,  120.0),
    'wlm': (5.0,  200.0),
    'wdm': (2.0,  150.0),
    'sm':  (2.0,  120.0),
    'c':   (0.01, 0.35),
    'ex':  (0.1,  4.0),
    'ki':  (0.01, 0.55),
    'kg':  (0.01, 0.55),
    'cs':  (0.1,  0.9),
    'ci':  (0.3,  0.95),
    'cg':  (0.5,  0.998),
    'beta_r': (0.1, 5.0),   # HBV 式幂律产流指数
}

POWER_RUNOFF_PARAM_NAMES = list(POWER_RUNOFF_PARAM_BOUNDS.keys())


def calibrate_xaj_power_runoff(rain: np.ndarray, pet: np.ndarray, obs: np.ndarray,
                                n_trials: int = 2000, n_restarts: int = 3) -> dict:
    """CMA-ES 多重启率定 XAJ + HBV式幂律产流 (13 参数)。"""
    return _cmaes_multi_restart(
        lambda rain_pet_p: simulate_xaj_power_runoff(rain_pet_p[0], rain_pet_p[1], rain_pet_p[2]),
        (rain, pet), obs, POWER_RUNOFF_PARAM_NAMES, POWER_RUNOFF_PARAM_BOUNDS,
        n_trials=n_trials, n_restarts=n_restarts,
    )


def calibrate_pdd_xaj(rain: np.ndarray, pet: np.ndarray, temp: np.ndarray,
                      obs: np.ndarray, n_trials: int = 5000, n_restarts: int = 3,
                      init_mean: float = 0.5, init_sigma: float = 0.3,
                      loss: str = 'nse', kge_weight: float = 0.5,
                      param_bounds: dict | None = None) -> dict:
    """CMA-ES 多重启率定 PDD+XAJ 耦合模型 (20 参数)。

    playbook knobs forwarded to ``_cmaes_multi_restart``. ``param_bounds`` lets a
    caller override the default bounds (for the bounds-widening lever) while
    keeping the 20-parameter ordering of ``PDD_XAJ_PARAM_NAMES``.
    """
    all_bounds = param_bounds if param_bounds is not None else {**PDD_PARAM_BOUNDS, **PARAM_BOUNDS}
    return _cmaes_multi_restart(
        lambda rpt_p: simulate_pdd_xaj(rpt_p[0], rpt_p[1], rpt_p[2], rpt_p[3]),
        (rain, pet, temp), obs, PDD_XAJ_PARAM_NAMES, all_bounds,
        n_trials=n_trials, n_restarts=n_restarts,
        init_mean=init_mean, init_sigma=init_sigma, loss=loss, kge_weight=kge_weight,
    )


# ---------------------------------------------------------------------------
# PDD + XAJ-SmoothET (22 参数)
# ---------------------------------------------------------------------------

PDD_SMOOTH_ET_PARAM_NAMES = PDD_PARAM_NAMES + SMOOTH_ET_PARAM_NAMES


def calibrate_pdd_xaj_smooth_et(rain: np.ndarray, pet: np.ndarray, temp: np.ndarray,
                                 obs: np.ndarray, n_trials: int = 5000, n_restarts: int = 3) -> dict:
    """CMA-ES 多重启率定 PDD+XAJ-SmoothET (22 参数)。"""
    all_bounds = {**PDD_PARAM_BOUNDS, **SMOOTH_ET_PARAM_BOUNDS}
    return _cmaes_multi_restart(
        lambda rpt_p: simulate_pdd_xaj_smooth_et(rpt_p[0], rpt_p[1], rpt_p[2], rpt_p[3]),
        (rain, pet, temp), obs, PDD_SMOOTH_ET_PARAM_NAMES, all_bounds,
        n_trials=n_trials, n_restarts=n_restarts,
    )


# ---------------------------------------------------------------------------
# PDD + XAJ-PowerRunoff (19 参数)
# ---------------------------------------------------------------------------

PDD_POWER_RUNOFF_PARAM_NAMES = PDD_PARAM_NAMES + POWER_RUNOFF_PARAM_NAMES


def calibrate_pdd_xaj_power_runoff(rain: np.ndarray, pet: np.ndarray, temp: np.ndarray,
                                    obs: np.ndarray, n_trials: int = 5000, n_restarts: int = 3) -> dict:
    """CMA-ES 多重启率定 PDD+XAJ-PowerRunoff (19 参数)。"""
    all_bounds = {**PDD_PARAM_BOUNDS, **POWER_RUNOFF_PARAM_BOUNDS}
    return _cmaes_multi_restart(
        lambda rpt_p: simulate_pdd_xaj_power_runoff(rpt_p[0], rpt_p[1], rpt_p[2], rpt_p[3]),
        (rain, pet, temp), obs, PDD_POWER_RUNOFF_PARAM_NAMES, all_bounds,
        n_trials=n_trials, n_restarts=n_restarts,
    )


# ---------------------------------------------------------------------------
# 通用多重启 CMA-ES
# ---------------------------------------------------------------------------

def _cmaes_multi_restart(sim_fn, forcing_tuple, obs, param_names, param_bounds,
                         n_trials=2000, n_restarts=3,
                         init_mean=0.5, init_sigma=0.3,
                         loss='nse', kge_weight=0.5,
                         constraint_fn=_enforce_ki_kg):
    """多重启 CMA-ES 率定，取最优结果。

    sim_fn: callable((*forcing_tuple, params_dict)) -> (q, state)

    Playbook knobs (default-preserving, so existing callers are unchanged):
    - init_mean / init_sigma : CMA-ES starting mean / step-size in [0,1] norm space.
    - loss : 'nse' | 'kge' | 'hybrid'. hybrid = (1-w)*(1-nse) + w*(1-kge).
    - constraint_fn : post-decode parameter constraint applied in-place to the
      param dict. Defaults to ``_enforce_ki_kg`` so all existing XAJ callers are
      byte-identical. GR4J (no ki/kg) passes ``constraint_fn=None``.
    """
    lo = np.array([param_bounds[n][0] for n in param_names])
    hi = np.array([param_bounds[n][1] for n in param_names])
    ndim = len(param_names)
    warmup = min(WARMUP_DAYS, len(obs) // 4)
    obs_eval = obs[warmup:]

    def objective(x_norm):
        x = lo + np.clip(x_norm, 0.0, 1.0) * (hi - lo)
        p = dict(zip(param_names, x.tolist()))
        if constraint_fn is not None:
            constraint_fn(p)
        try:
            q, _ = sim_fn((*forcing_tuple, p))
            q_eval = q[warmup:]
            if loss == 'nse':
                v = _nse(obs_eval, q_eval)
                return 1.0 - v if np.isfinite(v) else 2.0
            if loss == 'kge':
                v = _kge(obs_eval, q_eval)
                return 1.0 - v if np.isfinite(v) else 2.0
            if loss == 'hybrid':
                nse = _nse(obs_eval, q_eval)
                kge = _kge(obs_eval, q_eval)
                if not (np.isfinite(nse) and np.isfinite(kge)):
                    return 2.0
                return (1.0 - kge_weight) * (1.0 - nse) + kge_weight * (1.0 - kge)
            raise ValueError(f"Unknown loss: {loss}")
        except Exception:
            return 2.0

    best_overall = None
    for restart in range(n_restarts):
        seed = 42 + restart * 1000
        es = cma.CMAEvolutionStrategy([init_mean] * ndim, init_sigma, {
            'bounds': [[0.0] * ndim, [1.0] * ndim],
            'maxfevals': n_trials,
            'seed': seed,
            'verbose': -9,
        })
        es.optimize(objective)

        if best_overall is None or es.result.fbest < best_overall[1]:
            best_overall = (es.result.xbest.copy(), es.result.fbest)

    best_x = lo + np.clip(best_overall[0], 0.0, 1.0) * (hi - lo)
    best_params = dict(zip(param_names, best_x.tolist()))
    if constraint_fn is not None:
        constraint_fn(best_params)

    try:
        best_q, final_state = sim_fn((*forcing_tuple, best_params))
        q_eval = best_q[warmup:]
        best_nse = _nse(obs_eval, q_eval)
    except Exception:
        best_q = np.zeros(len(obs))
        final_state = None
        best_nse = -999.0

    return {
        'nse': float(best_nse),
        'optimized_params': best_params,
        'qsim': best_q,
        'final_state': final_state,
    }
