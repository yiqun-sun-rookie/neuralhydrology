"""Faithful NumPy port of the MATLAB fixed-step state-space WALRUS.

Source of truth: the audited toolbox snapshot
``paper-imm-variable-params/tmp/external/nutstore_func_public_snapshot_20260722/``
(``walrus_st_sp.m`` plus its subfunctions) and the synthetic-experiment wrapper
``statetran_fcn.m`` from the submission package. Operation order, guard
semantics (including the official min_h emergency values and the if/elseif
structure), and default constants are preserved exactly; see
``docs/plans/2026-07-22-walrus-imm-alignment-design.md``.
"""

from __future__ import annotations

import math

import numpy as np

AS_DEFAULT = 0.01
AG_DEFAULT = 1.0 - AS_DEFAULT

B_SOIL = 4.38
PSI_AE = 90.0
THETA_S = 0.41

ZETA1 = 0.02
ZETA2 = 400.0
EXP_S = 1.5
MIN_H = 0.001


def w_dv(dv: float, cw: float) -> float:
    """Cosine wetness index W(dV), clamped to [0, cw]."""
    return 0.5 * math.cos(max(min(dv, cw), 0.0) * math.pi / cw) + 0.5


def dveq_dg(dg: float, b: float = B_SOIL, psi_ae: float = PSI_AE, theta_s: float = THETA_S) -> float:
    """Equilibrium storage deficit dVeq(dG); MATLAB algebraic form."""
    if dg > psi_ae:
        dveq = dg - (psi_ae / (1.0 - b))
        dveq = dveq - (dg ** (1.0 - 1.0 / b)) * (psi_ae ** (1.0 / b)) / (1.0 - 1.0 / b)
        return dveq * theta_s
    if dg < 0.0:
        return dg
    return 0.0


def beta_dv(dv: float, zeta1: float = ZETA1, zeta2: float = ZETA2) -> float:
    """Evapotranspiration reduction beta(dV)."""
    beta = 1.0 - math.exp(zeta1 * (dv - zeta2))
    return beta / (1.0 + math.exp(zeta1 * (dv - zeta2))) * 0.5 + 0.5


def q_hs(hs: float, cs: float, cd: float, hs_min: float = 0.0, exps: float = EXP_S) -> float:
    """Stage-discharge power law with the above-bankfull extension."""
    if hs <= hs_min:
        return 0.0
    if hs <= cd:
        return cs * ((hs - hs_min) / (cd - hs_min)) ** exps
    return cs + cs * ((hs - cd) / (cd - hs_min)) ** exps


def pq_pv_ps(p_t: float, w: float, ag: float = AG_DEFAULT, as_: float = AS_DEFAULT) -> tuple[float, float, float]:
    """Split precipitation into quickflow, soil, and surface-water shares."""
    return p_t * w * ag, p_t * (1.0 - w) * ag, p_t * as_


def etv_ets_etact(
    etpot_t: float,
    dv: float,
    hs: float,
    as_: float = AS_DEFAULT,
    ag: float = AG_DEFAULT,
    zeta1: float = ZETA1,
    zeta2: float = ZETA2,
    min_h: float = MIN_H,
) -> tuple[float, float, float]:
    """Split potential evapotranspiration; no open-water share from an empty channel."""
    etv = etpot_t * beta_dv(dv, zeta1, zeta2) * ag
    ets = etpot_t * as_
    if hs < min_h * 1e3:
        ets = 0.0
    return etv, ets, etv + ets


def pond_flood(
    dv: float,
    hs: float,
    dg: float,
    cd: float,
    as_: float = AS_DEFAULT,
    ag: float = AG_DEFAULT,
) -> tuple[float, float, float]:
    """Large-scale ponding and flooding special case (all four MATLAB branches)."""
    if (dv < 0.0) or (hs > cd):
        if (dv < 0.0) and (hs <= cd):
            hs = hs + (-dv) * ag / as_
            dv = 0.0
        if (dv >= 0.0) and (hs > cd):
            dv = dv - (hs - cd) * as_ / ag
            hs = cd
        if (dv <= 0.0) and (hs >= cd):
            dv = dv * ag - (hs - cd) * as_
            hs = cd - dv
        if dv < 0.0:
            dg = dv
    return dv, hs, dg


def walrus_st_sp(
    state: np.ndarray,
    cw: float,
    cv: float,
    cg: float,
    cq: float,
    cd: float,
    cs: float,
    p_t: float,
    etpot_t: float,
    fxg_t: float = 0.0,
    fxs_t: float = 0.0,
    hs_min_t: float = 0.0,
    as_: float = AS_DEFAULT,
    ag: float | None = None,
) -> np.ndarray:
    """One fixed-step WALRUS transition on state [dv, dg, hq, hs, q]."""
    if ag is None:
        ag = 1.0 - as_

    dv0 = float(state[0])
    dg0 = float(state[1])
    hs0 = float(state[3])
    hq0 = max(float(state[2]), 0.0)
    q0 = max(float(state[4]), 0.0)

    w0 = w_dv(dv0, cw)
    dveq0 = dveq_dg(dg0)

    pq, pv, ps = pq_pv_ps(p_t, w0)
    etv, ets, _ = etv_ets_etact(etpot_t, dv0, hs0)
    fqs = hq0 / cq
    fgs = (cd - dg0 - hs0) * max(cd - dg0, hs0) / cg

    dv = dv0 - (fxg_t + pv - etv - fgs) / ag
    dg = dg0 + (dv0 - dveq0) / cv
    hq = hq0 + (pq - fqs) / ag
    hs = hs0 + (fxs_t + ps - ets + fgs + fqs - q0) / as_
    q = q_hs(hs, cs, cd, hs_min_t)

    dv, hs, dg = pond_flood(dv, hs, dg, cd, as_, ag)

    if hs < -0.001:
        hs = 100.0 * 0.001
    elif hq < -0.001:
        hq = 0.001

    q = max(q, 0.0)
    return np.array([dv, dg, hq, hs, q], dtype=np.float64)


def statetran(
    state: np.ndarray,
    p_t: float,
    etpot_t: float,
    noise: np.ndarray,
    cw: float,
    cv: float,
    cg: float,
    cq: float,
    cd: float,
    cs: float,
) -> np.ndarray:
    """Synthetic-experiment wrapper: model step plus additive noise plus guard.

    Mirrors ``statetran_fcn.m``: the guard re-checks stage/quickflow after the
    noise is added, with the same if/elseif precedence as the model core.
    """
    out = walrus_st_sp(state, cw, cv, cg, cq, cd, cs, p_t, etpot_t) + np.asarray(noise, dtype=np.float64)
    if out[3] < -0.001:
        out[3] = 100.0 * 0.001
    elif out[2] < -0.001:
        out[2] = 0.001
    return out
