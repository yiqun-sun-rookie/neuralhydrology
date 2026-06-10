"""Bounds saturation audit for a calibrated PDD+XAJ variant.

HBV-lite playbook technique 3: widen a bound only when calibration is pinned
against it for a meaningful fraction of basins. This reads the ``p_*`` columns
from a variant's per-basin csvs, normalizes each parameter to its [lo,hi] bound,
and reports the fraction of basins within ``--tol`` of the lower / upper bound.

Usage::

    python -X utf8 -m src.xaj_global_pilot.scripts.saturation_audit iter2_pt_warmup
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

_ROOT = Path("results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01")


def main(argv=None) -> int:
    import sys
    sys.path.insert(0, "src")
    from xaj_global_pilot.xaj_model import PDD_PARAM_BOUNDS, PARAM_BOUNDS, PDD_XAJ_PARAM_NAMES
    from xaj_global_pilot.bounds_presets import resolve_xaj_bounds

    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("subdir")
    p.add_argument("--subset", default="src/xaj_global_pilot/configs/xaj_playbook_iter_subset_40.txt")
    p.add_argument("--tol", type=float, default=0.02, help="fraction-of-range tolerance for 'pinned'")
    p.add_argument("--bounds-preset", default="v1",
                   help="Bounds preset the variant was CALIBRATED with — must match, "
                        "else params are audited against the wrong range.")
    args = p.parse_args(argv)

    # Audit against the bounds the variant was actually calibrated with.
    bounds = resolve_xaj_bounds(args.bounds_preset, PDD_PARAM_BOUNDS, PARAM_BOUNDS)
    subset = [l.strip().zfill(8) for l in Path(args.subset).read_text().splitlines() if l.strip()]
    vdir = _ROOT / args.subdir
    rows = []
    for b in subset:
        f = vdir / f"{b}.csv"
        if f.exists():
            rows.append(pd.read_csv(f, dtype={"basin_id": str}, keep_default_na=False).iloc[0])
    if not rows:
        print(f"No csvs in {vdir}")
        return 1
    df = pd.DataFrame(rows)
    n = len(df)
    print(f"Saturation audit: {args.subdir}  ({n} basins, tol={args.tol:.0%} of range)")
    print(f"{'param':<18}{'lo':>9}{'hi':>9}{'%@lo':>7}{'%@hi':>7}{'median':>10}")
    print("-" * 70)
    flagged = []
    for name in PDD_XAJ_PARAM_NAMES:
        col = f"p_{name}"
        if col not in df.columns:
            continue
        lo, hi = bounds[name]
        vals = pd.to_numeric(df[col], errors="coerce").dropna().values
        if vals.size == 0:
            continue
        rng = hi - lo
        norm = (vals - lo) / rng if rng > 0 else np.zeros_like(vals)
        at_lo = float((norm <= args.tol).mean()) * 100
        at_hi = float((norm >= 1 - args.tol).mean()) * 100
        mark = ""
        if at_hi >= 20:
            mark = "  <-- widen UPPER"; flagged.append((name, "hi", at_hi))
        elif at_lo >= 20:
            mark = "  <-- widen LOWER"; flagged.append((name, "lo", at_lo))
        print(f"{name:<18}{lo:>9.3f}{hi:>9.3f}{at_lo:>7.0f}{at_hi:>7.0f}{np.median(vals):>10.3f}{mark}")
    print("-" * 70)
    if flagged:
        print("FLAGGED (>=20% pinned):", ", ".join(f"{n}@{s}({p:.0f}%)" for n, s, p in flagged))
    else:
        print("No parameter pinned >=20% — bounds widening unlikely to help.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
