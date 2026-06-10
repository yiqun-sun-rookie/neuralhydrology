"""NumPy + Numba HBV-lite forward simulation.

Bit-for-bit equivalent of ``DifferentiableHBVLite._PBM`` (PyTorch), but
written in plain NumPy with ``@njit`` decorators so it runs ~10-50×
faster than the PyTorch version. Designed for derivative-free
calibration (CMA-ES) where autograd is not needed.

States (5): SNOWPACK, MELTWATER, SM, SUZ, SLZ
Parameters (12 phy + 1 lag): same as hbv_lite.py

Use ``simulate_hbv_lite`` for standalone simulation or as the forward
inside ``hbv_lite_cma_calibrate.calibrate_hbv_lite_cma``.
"""
import os as _os
from typing import Optional, Tuple

import numpy as np

try:
    if _os.environ.get("DISABLE_NUMBA") == "1":
        raise ImportError("Disabled via env")
    from numba import njit
    _HAS_NUMBA = True
except Exception:
    _HAS_NUMBA = False

    def njit(*args, **kwargs):  # noqa: D401
        """Identity fallback when numba is unavailable."""
        if args and callable(args[0]):
            return args[0]

        def wrap(f):
            return f

        return wrap


PARAM_NAMES = [
    "parTT", "parCFMAX", "parCFR", "parCWH",
    "parFC", "parBETA", "parLP",
    "parK0", "parK1", "parUZL", "parPERC",
    "parK2",
    "lag_time",
]
STATE_NAMES = ["SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ"]

# Switchable PARAM_BOUNDS — controlled by HBV_BOUNDS env var.
# 'v1' = hydroDL2 defaults (Feng et al. 2022 WRR)
# 'v5' = wider bounds (allow some basins more headroom)
_BOUNDS_V1 = {
    "parTT":    (-2.5, 2.5),
    "parCFMAX": (0.5, 10.0),
    "parCFR":   (0.0, 0.1),
    "parCWH":   (0.0, 0.2),
    "parFC":    (50.0, 1000.0),
    "parBETA":  (1.0, 6.0),
    "parLP":    (0.2, 1.0),
    "parK0":    (0.05, 0.9),
    "parK1":    (0.01, 0.5),
    "parUZL":   (0.0, 100.0),
    "parPERC":  (0.0, 10.0),
    "parK2":    (0.001, 0.2),
    "lag_time": (1.0, 10.0),
}
_BOUNDS_V5 = {
    "parTT":    (-2.5, 2.5),
    "parCFMAX": (0.5, 15.0),
    "parCFR":   (0.0, 0.1),
    "parCWH":   (0.0, 0.2),
    "parFC":    (50.0, 2500.0),
    "parBETA":  (1.0, 6.0),
    "parLP":    (0.2, 1.0),
    "parK0":    (0.05, 0.99),
    "parK1":    (0.01, 0.5),
    "parUZL":   (0.0, 200.0),
    "parPERC":  (0.0, 30.0),
    "parK2":    (0.0001, 0.5),
    "lag_time": (1.0, 15.0),
}
_BOUNDS_PRESET = _os.environ.get("HBV_BOUNDS", "v5").lower()
if _BOUNDS_PRESET == "v1":
    PARAM_BOUNDS = _BOUNDS_V1
else:
    PARAM_BOUNDS = _BOUNDS_V5

# Named presets so bounds can be selected at RUNTIME (passed to the calibrator
# via ``param_bounds=``) instead of relying on the import-time HBV_BOUNDS env
# var. The env mechanism above is a reproducibility footgun: the repro_v01
# headline used 'v1' but the module default is 'v5', so a run's bounds could not
# be recovered from a CLI flag. Mirrors xaj_global_pilot.bounds_presets and
# gr4j_model.resolve_gr4j_bounds so all three runners share one CLI shape.
BOUNDS_PRESETS = {"v1": _BOUNDS_V1, "v5": _BOUNDS_V5}


def resolve_hbv_bounds(preset: str) -> dict:
    """Return the 13-parameter HBV-lite bounds dict for ``preset``.

    'v1' = hydroDL2 literature-tight (Feng et al. 2022 WRR).
    'v5' = wider bounds (extra headroom for some basins).

    The returned dict is a fresh copy (tuple values) so callers cannot mutate
    the module presets. Raises ``ValueError`` on an unknown preset.
    """
    key = preset.lower()
    if key not in BOUNDS_PRESETS:
        raise ValueError(
            f"Unknown HBV bounds preset {preset!r}. Known: {sorted(BOUNDS_PRESETS)}")
    return {name: tuple(rng) for name, rng in BOUNDS_PRESETS[key].items()}


@njit(cache=True, fastmath=True)
def _simulate_loop(
    rain: np.ndarray,
    pet: np.ndarray,
    temp: np.ndarray,
    SP0: float, WC0: float, SM0: float, SUZ0: float, SLZ0: float,
    TT: float, CFMAX: float, CFR: float, CWH: float,
    FC: float, BETA: float, LP: float,
    K0: float, K1: float, UZL: float, PERC: float,
    K2: float,
) -> Tuple[np.ndarray, float, float, float, float, float]:
    """Core HBV-light time loop. Returns (q_raw_per_day, final SP/WC/SM/SUZ/SLZ).

    Mirrors hydroDL2 hbv.py::_PBM exactly (eps=1e-5 to match).
    """
    T = rain.shape[0]
    q_raw = np.zeros(T, dtype=np.float64)

    eps = 1e-5
    SP = SP0
    WC = WC0
    SM = SM0
    SUZ = SUZ0
    SLZ = SLZ0

    for t in range(T):
        P = rain[t]
        Tm = temp[t]
        PETt = pet[t]

        # Snow ------------------------------------------------------------
        if Tm < TT:
            SNOW = P
            RAIN = 0.0
        else:
            SNOW = 0.0
            RAIN = P

        SP = SP + SNOW
        melt = CFMAX * (Tm - TT)
        if melt < 0.0:
            melt = 0.0
        if melt > SP:
            melt = SP
        WC = WC + melt
        SP = SP - melt

        refreezing = CFR * CFMAX * (TT - Tm)
        if refreezing < 0.0:
            refreezing = 0.0
        if refreezing > WC:
            refreezing = WC
        SP = SP + refreezing
        WC = WC - refreezing

        tosoil = WC - CWH * SP
        if tosoil < 0.0:
            tosoil = 0.0
        WC = WC - tosoil

        # Soil + ET -------------------------------------------------------
        ratio = SM / (FC + eps)
        if ratio < 0.0:
            ratio = 0.0
        if ratio > 1.0:
            ratio = 1.0
        soil_wetness = ratio ** BETA
        if soil_wetness < 0.0:
            soil_wetness = 0.0
        if soil_wetness > 1.0:
            soil_wetness = 1.0
        recharge = (RAIN + tosoil) * soil_wetness
        SM = SM + RAIN + tosoil - recharge

        excess = SM - FC
        if excess < 0.0:
            excess = 0.0
        SM = SM - excess

        evapfactor = SM / (LP * FC + eps)
        if evapfactor < 0.0:
            evapfactor = 0.0
        if evapfactor > 1.0:
            evapfactor = 1.0
        ETact = PETt * evapfactor
        if ETact > SM:
            ETact = SM
        SM = SM - ETact
        if SM < eps:
            SM = eps

        # Groundwater -----------------------------------------------------
        SUZ = SUZ + recharge + excess
        perc_flux = PERC
        if perc_flux > SUZ:
            perc_flux = SUZ
        SUZ = SUZ - perc_flux
        uz_excess = SUZ - UZL
        if uz_excess < 0.0:
            uz_excess = 0.0
        Q0 = K0 * uz_excess
        SUZ = SUZ - Q0
        Q1 = K1 * SUZ
        SUZ = SUZ - Q1
        SLZ = SLZ + perc_flux
        Q2 = K2 * SLZ
        SLZ = SLZ - Q2

        q_raw[t] = Q0 + Q1 + Q2

    return q_raw, SP, WC, SM, SUZ, SLZ


def _half_triangular_lag(q_raw: np.ndarray, lag_time: float) -> np.ndarray:
    """Apply RECESSION-half triangular routing lag (peak at current day).

    With ``n = ceil(lag_time)`` and weights ``w_k = (n-k)/sum`` for
    ``k = 0..n-1``, the simulated discharge at day ``t`` is::

        q_sim[t] = w_0 * q_raw[t] + w_1 * q_raw[t-1] + ... + w_{n-1} * q_raw[t-n+1]

    where ``w_0`` is the LARGEST weight. Interpretation: today's raw runoff
    contributes its largest share to today's outlet flow, with a linearly
    decaying tail over the following ``n-1`` days. Peak at t=0.

    NOTE: This DIFFERS from the rising-half triangular UH in the PyTorch
    DifferentiableHBVLite._triangular_lag_batch implementation (peak at
    t = n-1, delayed by lag-1 days). Same parameters produce different
    streamflow under the two implementations. See
    ``docs/technical/camels_531_lockdown_report_20260602.md`` for the
    canonical choice rationale.
    """
    n = max(int(np.ceil(lag_time)), 1)
    weights = np.arange(1, n + 1, dtype=np.float64)
    weights = weights / weights.sum()
    T = q_raw.shape[0]
    q_out = np.zeros(T, dtype=np.float64)
    for t in range(T):
        s = 0.0
        for k in range(n):
            if t - k >= 0:
                s = s + weights[n - 1 - k] * q_raw[t - k]
        q_out[t] = s
    return q_out


def simulate_hbv_lite(
    rain: np.ndarray,
    pet: np.ndarray,
    temp: np.ndarray,
    params: dict,
    initial_state: Optional[dict] = None,
) -> Tuple[np.ndarray, dict]:
    """Simulate HBV-light over a time series.

    Args:
        rain/pet/temp: 1D arrays of length T (mm/d, mm/d, °C).
        params: dict with the 13 named parameters.
        initial_state: optional dict with SNOWPACK / MELTWATER / SM / SUZ / SLZ.

    Returns:
        q_sim: 1D array length T, post-lag simulated discharge (mm/d).
        final_state: dict with end states.
    """
    rain = np.asarray(rain, dtype=np.float64)
    pet = np.asarray(pet, dtype=np.float64)
    temp = np.asarray(temp, dtype=np.float64)

    if initial_state is not None:
        SP0 = float(initial_state.get("SNOWPACK", 0.0))
        WC0 = float(initial_state.get("MELTWATER", 0.0))
        SM0 = float(initial_state.get("SM", params["parFC"] * 0.3))
        SUZ0 = float(initial_state.get("SUZ", 5.0))
        SLZ0 = float(initial_state.get("SLZ", 10.0))
    else:
        SP0 = 0.0
        WC0 = 0.0
        SM0 = float(params["parFC"]) * 0.3
        SUZ0 = 5.0
        SLZ0 = 10.0

    q_raw, SP, WC, SM, SUZ, SLZ = _simulate_loop(
        rain, pet, temp,
        SP0, WC0, SM0, SUZ0, SLZ0,
        float(params["parTT"]),
        float(params["parCFMAX"]),
        float(params["parCFR"]),
        float(params["parCWH"]),
        float(params["parFC"]),
        float(params["parBETA"]),
        float(params["parLP"]),
        float(params["parK0"]),
        float(params["parK1"]),
        float(params["parUZL"]),
        float(params["parPERC"]),
        float(params["parK2"]),
    )
    q_sim = _half_triangular_lag(q_raw, float(params["lag_time"]))
    final_state = {
        "SNOWPACK": SP,
        "MELTWATER": WC,
        "SM": SM,
        "SUZ": SUZ,
        "SLZ": SLZ,
    }
    return np.maximum(q_sim, 0.0), final_state
