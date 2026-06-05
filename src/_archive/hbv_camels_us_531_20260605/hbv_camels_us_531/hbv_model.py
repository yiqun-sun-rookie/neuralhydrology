"""Pure NumPy HBV model — no SuperflexPy dependency.

Structure: Snow → Soil (UnsaturatedReservoir) → Fast (Power) + Slow (Linear) → Lag → Q
Parameters (10):
    t0      : snow/rain threshold temperature [°C]
    k_snow  : snowmelt degree-day factor [mm/°C/d]
    Smax    : max soil moisture storage [mm]
    Ce      : evapotranspiration coefficient [-]
    beta    : soil moisture recharge exponent [-]
    split   : fraction of recharge to fast reservoir [-]
    k_fast  : fast reservoir recession coefficient [1/d]
    alpha   : fast reservoir nonlinearity exponent [-]
    k_slow  : slow reservoir recession coefficient [1/d]
    lag_time: triangular lag time [d]
"""
from __future__ import annotations

import numpy as np
import cma

# Parameter names, defaults, and bounds (order matters)
PARAM_NAMES = ['t0', 'k_snow', 'Smax', 'Ce', 'beta', 'split', 'k_fast', 'alpha', 'k_slow', 'lag_time']
PARAM_BOUNDS = {
    't0':       (-3.0,   3.0),
    'k_snow':   ( 0.5,   5.0),
    'Smax':     (50.0, 500.0),
    'Ce':       ( 0.3,   1.5),
    'beta':     ( 1.0,   5.0),
    'split':    ( 0.1,   0.9),
    'k_fast':   ( 0.001, 0.5),
    'alpha':    ( 1.0,   3.0),
    'k_slow':   ( 0.001, 0.1),
    'lag_time': ( 1.0,  10.0),
}


def simulate_hbv(
    rain: np.ndarray,
    pet: np.ndarray,
    temp: np.ndarray,
    params: dict[str, float],
    initial_state: dict | None = None,
) -> tuple[np.ndarray, dict]:
    """Run HBV forward simulation (explicit Euler, daily step).

    Args:
        rain: precipitation [mm/d], shape (T,)
        pet: potential ET [mm/d], shape (T,)
        temp: mean temperature [°C], shape (T,)
        params: parameter dict with keys from PARAM_NAMES
        initial_state: optional dict with S_snow, S_soil, S_fast, S_slow

    Returns:
        q: total discharge [mm/d], shape (T,)
        final_state: dict of final storage states
    """
    T = len(rain)
    t0 = params['t0']
    k_snow = params['k_snow']
    Smax = params['Smax']
    Ce = params['Ce']
    beta = params['beta']
    split = params['split']
    k_fast = params['k_fast']
    alpha = params['alpha']
    k_slow = params['k_slow']
    lag_time = params['lag_time']

    # Initial states
    if initial_state is not None:
        S_snow = initial_state.get('S_snow', 0.0)
        S_soil = initial_state.get('S_soil', Smax * 0.3)
        S_fast = initial_state.get('S_fast', 5.0)
        S_slow = initial_state.get('S_slow', 5.0)
    else:
        S_snow = 0.0
        S_soil = Smax * 0.3
        S_fast = 5.0
        S_slow = 5.0

    q_raw = np.zeros(T)

    for t in range(T):
        P = rain[t]
        PET = pet[t]
        Tm = temp[t]

        # --- Snow module ---
        if Tm < t0:
            snowfall = P
            rainfall = 0.0
        else:
            snowfall = 0.0
            rainfall = P
        S_snow += snowfall
        melt = min(k_snow * max(Tm - t0, 0.0), S_snow)
        S_snow -= melt
        P_eff = rainfall + melt

        # --- Soil moisture (unsaturated zone) ---
        # Recharge: fraction of P_eff that becomes runoff
        s_ratio = min(max(S_soil / Smax, 0.0), 1.0)
        recharge = P_eff * (s_ratio ** beta)
        # Actual ET
        aet = Ce * PET * min(s_ratio, 1.0)
        # Update soil storage
        S_soil = S_soil + P_eff - recharge - aet
        S_soil = max(S_soil, 0.0)
        S_soil = min(S_soil, Smax)

        # --- Fast reservoir (power law) ---
        q_fast = k_fast * (S_fast ** alpha) if S_fast > 0 else 0.0
        q_fast = min(q_fast, S_fast + split * recharge)  # can't drain more than available
        S_fast = S_fast + split * recharge - q_fast
        S_fast = max(S_fast, 0.0)

        # --- Slow reservoir (linear) ---
        q_slow = k_slow * S_slow
        q_slow = min(q_slow, S_slow + (1.0 - split) * recharge)
        S_slow = S_slow + (1.0 - split) * recharge - q_slow
        S_slow = max(S_slow, 0.0)

        q_raw[t] = q_fast + q_slow

    # --- Triangular lag routing ---
    q = _triangular_lag(q_raw, lag_time)

    final_state = {'S_snow': S_snow, 'S_soil': S_soil, 'S_fast': S_fast, 'S_slow': S_slow}
    return q, final_state


def _triangular_lag(q: np.ndarray, lag_time: float) -> np.ndarray:
    """Apply half-triangular unit hydrograph routing."""
    n = max(int(np.ceil(lag_time)), 1)
    weights = np.arange(1, n + 1, dtype=np.float64)
    weights = weights / weights.sum()
    return np.convolve(q, weights, mode='full')[:len(q)]


def _nse(obs: np.ndarray, sim: np.ndarray) -> float:
    mask = np.isfinite(obs) & np.isfinite(sim)
    if mask.sum() < 10:
        return -999.0
    o, s = obs[mask], sim[mask]
    denom = np.sum((o - o.mean()) ** 2)
    if denom < 1e-12:
        return -999.0
    return float(1.0 - np.sum((o - s) ** 2) / denom)


WARMUP_DAYS = 365


def calibrate_hbv(
    rain: np.ndarray,
    pet: np.ndarray,
    temp: np.ndarray,
    obs: np.ndarray,
    n_trials: int = 2000,
    n_restarts: int = 3,
) -> dict:
    """CMA-ES 多重启率定 HBV。Returns dict with nse, optimized_params, qsim, final_state."""
    lo = np.array([PARAM_BOUNDS[n][0] for n in PARAM_NAMES])
    hi = np.array([PARAM_BOUNDS[n][1] for n in PARAM_NAMES])
    ndim = len(PARAM_NAMES)
    warmup = min(WARMUP_DAYS, len(obs) // 4)
    obs_eval = obs[warmup:]

    def objective(x_norm):
        x = lo + np.clip(x_norm, 0.0, 1.0) * (hi - lo)
        params = dict(zip(PARAM_NAMES, x.tolist()))
        try:
            q, _ = simulate_hbv(rain, pet, temp, params)
            q_eval = q[warmup:]
            nse = _nse(obs_eval, q_eval)
            return 1.0 - nse if np.isfinite(nse) else 2.0
        except Exception:
            return 2.0

    best_overall = None
    for restart in range(n_restarts):
        seed = 42 + restart * 1000
        es = cma.CMAEvolutionStrategy([0.5] * ndim, 0.3, {
            'bounds': [[0.0] * ndim, [1.0] * ndim],
            'maxfevals': n_trials,
            'seed': seed,
            'verbose': -9,
        })
        es.optimize(objective)

        if best_overall is None or es.result.fbest < best_overall[1]:
            best_overall = (es.result.xbest.copy(), es.result.fbest)

    best_x = lo + np.clip(best_overall[0], 0.0, 1.0) * (hi - lo)
    best_params = dict(zip(PARAM_NAMES, best_x.tolist()))
    try:
        best_q, final_state = simulate_hbv(rain, pet, temp, best_params)
        q_eval = best_q[warmup:]
        best_nse = _nse(obs_eval, q_eval)
    except Exception:
        best_q = np.zeros(len(obs))
        final_state = None
        best_nse = -999.0

    return {'nse': float(best_nse), 'optimized_params': best_params,
            'qsim': best_q, 'final_state': final_state}
