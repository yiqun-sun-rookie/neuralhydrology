"""CMA-ES calibration for NumPy HBV-lite.

Uses ``cma.CMAEvolutionStrategy`` (pycma) to optimize the 13 parameters
against an NSE-based objective. CMA-ES is derivative-free, so it sidesteps
the gradient-vanishing pathologies that hurt Adam on HBV-light's
many ``clamp`` / ``minimum`` operations (especially on arid basins where
``SUZ < UZL`` permanently zeros out K0/UZL gradients).

Mirrors the multi-restart pattern in
``src/xaj_global_pilot/xaj_model.py::_cmaes_multi_restart``.
"""
import numpy as np
import cma

from .hbv_lite_numpy import (
    PARAM_NAMES,
    PARAM_BOUNDS,
    STATE_NAMES,
    simulate_hbv_lite,
)

WARMUP_DAYS = 365


def _nse(obs: np.ndarray, sim: np.ndarray) -> float:
    mask = np.isfinite(obs) & np.isfinite(sim)
    if mask.sum() < 10:
        return float("nan")
    o = obs[mask]
    s = sim[mask]
    denom = np.sum((o - o.mean()) ** 2)
    if denom <= 0.0:
        return float("nan")
    return float(1.0 - np.sum((s - o) ** 2) / denom)


def _kge(obs: np.ndarray, sim: np.ndarray) -> float:
    """Kling-Gupta efficiency.

    KGE = 1 - sqrt((r-1)^2 + (alpha-1)^2 + (beta-1)^2)
    where r=corr, alpha=std(sim)/std(obs), beta=mean(sim)/mean(obs).
    Decomposes error into correlation + variance + bias components,
    often finds different optima than pure NSE.
    """
    mask = np.isfinite(obs) & np.isfinite(sim)
    if mask.sum() < 10:
        return float("nan")
    o = obs[mask]
    s = sim[mask]
    o_mean = o.mean()
    s_mean = s.mean()
    o_std = o.std()
    s_std = s.std()
    if o_std == 0 or o_mean == 0:
        return float("nan")
    r_num = np.sum((o - o_mean) * (s - s_mean))
    r_den = np.sqrt(np.sum((o - o_mean) ** 2) * np.sum((s - s_mean) ** 2))
    if r_den == 0:
        return float("nan")
    r = r_num / r_den
    alpha = s_std / o_std
    beta = s_mean / o_mean
    return float(1.0 - np.sqrt((r - 1) ** 2 + (alpha - 1) ** 2 + (beta - 1) ** 2))


def calibrate_hbv_lite_cma(
    rain: np.ndarray,
    pet: np.ndarray,
    temp: np.ndarray,
    obs: np.ndarray,
    n_trials: int = 5000,
    n_restarts: int = 3,
    state_init: dict | None = None,
    loss: str = "nse",
    kge_weight: float = 0.5,
    init_mean_norm: float | None = None,
    init_sigma: float = 0.3,
) -> dict:
    """CMA-ES multi-restart calibration of HBV-light.

    Parameters
    ----------
    rain, pet, temp, obs : np.ndarray (1D)
        Daily forcing and observed Q (mm/d).
    n_trials : int
        Max CMA-ES function evaluations per restart.
    n_restarts : int
        Independent CMA-ES runs (different seeds), best retained.

    Returns
    -------
    dict with: nse, optimized_params, qsim, final_state.
    """
    lo = np.array([PARAM_BOUNDS[n][0] for n in PARAM_NAMES])
    hi = np.array([PARAM_BOUNDS[n][1] for n in PARAM_NAMES])
    ndim = len(PARAM_NAMES)
    warmup = min(WARMUP_DAYS, len(obs) // 4)
    obs_eval = obs[warmup:]

    def _make_params(x_norm: np.ndarray) -> dict:
        x = lo + np.clip(x_norm, 0.0, 1.0) * (hi - lo)
        return dict(zip(PARAM_NAMES, x.tolist()))

    def objective(x_norm: np.ndarray) -> float:
        params = _make_params(x_norm)
        try:
            q_sim, _ = simulate_hbv_lite(rain, pet, temp, params, initial_state=state_init)
            q_eval = q_sim[warmup:]
            if loss == "nse":
                nse = _nse(obs_eval, q_eval)
                return 1.0 - nse if np.isfinite(nse) else 2.0
            if loss == "kge":
                kge = _kge(obs_eval, q_eval)
                return 1.0 - kge if np.isfinite(kge) else 2.0
            if loss == "hybrid":
                nse = _nse(obs_eval, q_eval)
                kge = _kge(obs_eval, q_eval)
                if not (np.isfinite(nse) and np.isfinite(kge)):
                    return 2.0
                return (1.0 - kge_weight) * (1.0 - nse) + kge_weight * (1.0 - kge)
            raise ValueError(f"Unknown loss: {loss}")
        except Exception:
            return 2.0

    init_m = 0.5 if init_mean_norm is None else float(init_mean_norm)
    best_overall: tuple[np.ndarray, float] | None = None
    for restart in range(n_restarts):
        seed = 42 + restart * 1000
        es = cma.CMAEvolutionStrategy(
            [init_m] * ndim,
            init_sigma,
            {
                "bounds": [[0.0] * ndim, [1.0] * ndim],
                "maxfevals": n_trials,
                "seed": seed,
                "verbose": -9,
            },
        )
        es.optimize(objective)
        if best_overall is None or es.result.fbest < best_overall[1]:
            best_overall = (es.result.xbest.copy(), float(es.result.fbest))

    if best_overall is None:
        return {
            "nse": -999.0,
            "optimized_params": {},
            "qsim": np.zeros(len(obs)),
            "final_state": None,
        }

    best_params = _make_params(best_overall[0])
    try:
        best_q, final_state = simulate_hbv_lite(rain, pet, temp, best_params, initial_state=state_init)
        best_nse = _nse(obs_eval, best_q[warmup:])
    except Exception:
        best_q = np.zeros(len(obs))
        final_state = None
        best_nse = -999.0

    return {
        "nse": float(best_nse) if np.isfinite(best_nse) else -999.0,
        "optimized_params": best_params,
        "qsim": np.maximum(best_q, 0.0),
        "final_state": final_state,
    }
