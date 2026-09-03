#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/id23_param_probe
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final
cd "$ROOT" || exit 1
python - <<'PY' 2>&1
import csv
import numpy as np
from pathlib import Path
ROOT = Path("/data1/home/sunyiq/id23_param_probe")
rng = np.random.default_rng(20260903)

def boot_median(x, n=10000):
    x = np.asarray([v for v in x if np.isfinite(v)], float)
    if x.size < 3: return (np.nan, np.nan)
    idx = rng.integers(0, x.size, size=(n, x.size))
    meds = np.median(x[idx], axis=1)
    return float(np.percentile(meds, 2.5)), float(np.percentile(meds, 97.5))

def sign_test(x):
    x = np.asarray([v for v in x if np.isfinite(v)], float)
    return int((x > 0).sum()), int((x < 0).sum()), int((x == 0).sum())

for window, in (("main",), ("sub",)):
    rows = list(csv.DictReader(open(ROOT / f"out/basin_results_{window}.csv")))
    print(f"\n########## {window} ##########")
    for scale in ("water_year", "block90"):
        s = [r for r in rows if r["scale"] == scale and r["metric"] == "nse"]
        og = [float(r["oracle_gain"]) for r in s]
        si = [float(r["switch_increment"]) for r in s]
        lo, hi = boot_median(og)
        slo, shi = boot_median(si)
        pos, neg, zer = sign_test(og)
        print(f"\n--- {scale} | nse  (n={len(s)}) ---")
        print(f"  oracle_gain      median={np.median(og):+.5f}  95% CI [{lo:+.5f}, {hi:+.5f}]"
              f"   win/loss/tie = {pos}/{neg}/{zer}")
        print(f"  switch_increment median={np.median(si):+.5f}  95% CI [{slo:+.5f}, {shi:+.5f}]")
        # robustness: drop collapsed candidate sets
        keep = [r for r in s if r["candidate_collapse"] != "True"]
        if keep:
            k_og = [float(r["oracle_gain"]) for r in keep]
            k_si = [float(r["switch_increment"]) for r in keep]
            print(f"  NO-COLLAPSE subset (n={len(keep)}): oracle_gain median={np.median(k_og):+.5f}"
                  f"   switch_increment median={np.median(k_si):+.5f}")
        drop = [r for r in s if r["candidate_collapse"] == "True"]
        if drop:
            d_og = [float(r["oracle_gain"]) for r in drop]
            print(f"  COLLAPSED subset  (n={len(drop)}): oracle_gain median={np.median(d_og):+.5f}")
        # attribution: which candidate does the oracle actually pick?
        p0 = sum(int(r["oracle_picks_cand0"]) for r in s)
        p1 = sum(int(r["oracle_picks_cand1"]) for r in s)
        p2 = sum(int(r["oracle_picks_cand2"]) for r in s)
        tot = p0 + p1 + p2
        print(f"  oracle segment picks: center={p0} ({100*p0/tot:.0f}%)  x0.5={p1} ({100*p1/tot:.0f}%)"
              f"  x2.0={p2} ({100*p2/tot:.0f}%)   total segments={tot}")
        # does the oracle need BOTH directions within one basin (true time variation)?
        both = sum(1 for r in s if int(r["oracle_picks_cand1"]) > 0 and int(r["oracle_picks_cand2"]) > 0)
        one = sum(1 for r in s if (int(r["oracle_picks_cand1"]) > 0) != (int(r["oracle_picks_cand2"]) > 0))
        none = sum(1 for r in s if int(r["oracle_picks_cand1"]) == 0 and int(r["oracle_picks_cand2"]) == 0)
        print(f"  basins needing BOTH x0.5 and x2.0 segments: {both}/{len(s)}"
              f"   one direction only: {one}   never leaves center: {none}")
PY
