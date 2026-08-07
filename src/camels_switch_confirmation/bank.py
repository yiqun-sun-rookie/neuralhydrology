"""Candidate-bank construction rule (prereg v01, decision B: parFC single-parameter).

One frozen formula applied identically to every basin — no per-basin tuning:
    member 1 = the basin's calibrated optimum (rising-kernel table)
    member 2 = same but parFC x 0.75
    member 3 = same but parFC x 4/3
parFC is clipped to the calibration bounds preset; a clipped member is flagged
so the G1 precheck can surface banks whose separation collapsed at the bound
(no manual rescue, per prereg section 3.2).
"""
from __future__ import annotations

FC_FACTORS = (1.0, 0.75, 4.0 / 3.0)


def build_bank(params: dict, fc_bounds: tuple) -> tuple:
    """Return ([member1, member2, member3], [clipped1, clipped2, clipped3]).

    Each member is a full 13-parameter dict; only parFC differs.
    """
    lo, hi = float(fc_bounds[0]), float(fc_bounds[1])
    members, clipped = [], []
    for factor in FC_FACTORS:
        p = dict(params)
        fc = float(params["parFC"]) * factor
        was_clipped = fc < lo or fc > hi
        p["parFC"] = min(max(fc, lo), hi)
        members.append(p)
        clipped.append(bool(was_clipped))
    return members, clipped
