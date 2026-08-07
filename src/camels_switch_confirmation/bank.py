"""Candidate-bank construction rule (prereg v01, decision B: parFC single-parameter).

One frozen formula applied identically to every basin — no per-basin tuning:
    member 1 = the basin's calibrated optimum (rising-kernel table)
    member 2 = same but parFC x 0.5   (half storage)
    member 3 = same but parFC x 2.0   (double storage)

Amendment 2026-08-07 (user decision "拉开差距"): factors widened from
(0.75, 4/3) after a 531-basin scan showed the old members were too close in
real-obs effect (median low-side NSE gap 0.074, high-side 0.026). At
(0.5, 2.0) the low-side gap is 0.743 and 448/531 basins shift NSE by >0.1.
The high side saturates (~0.09 even at x2, 0.146 at x2.5) because many soils
never fill regardless of capacity — a structural asymmetry of parFC, not a
factor choice. Scan artifact: results/23_camels_switch_confirmation/factor_scan.csv
parFC is clipped to the calibration bounds preset; a clipped member is flagged
so the G1 precheck can surface banks whose separation collapsed at the bound
(no manual rescue, per prereg section 3.2).
"""
from __future__ import annotations

FC_FACTORS = (1.0, 0.5, 2.0)


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
