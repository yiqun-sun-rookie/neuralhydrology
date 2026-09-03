#!/bin/bash
# Read-only digest of the probe outputs: decomposition, outliers, robustness.
set -o pipefail
ROOT=/data1/home/sunyiq/id23_param_probe
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final
cd "$ROOT" || exit 1
ls -la out/
python - <<'PY' 2>&1
import csv, json
import numpy as np
from pathlib import Path
ROOT = Path("/data1/home/sunyiq/id23_param_probe")

def med(a):
    a = np.asarray([x for x in a if np.isfinite(x)], float)
    return float(np.median(a)) if a.size else float("nan")

for window in ("main", "sub"):
    rows = list(csv.DictReader(open(ROOT / f"out/basin_results_{window}.csv")))
    for r in rows:
        for k in ("center","pick_one","oracle","causal","pick_one_gain","switch_increment",
                  "oracle_gain","causal_regret"):
            r[k] = float(r[k])
        r["n_segments_switched"] = int(r["n_segments_switched"])
    print(f"\n################ WINDOW = {window}  (rows={len(rows)}) ################")
    for scale in ("water_year","block90"):
        for metric in ("nse","log_nse"):
            s = [r for r in rows if r["scale"]==scale and r["metric"]==metric]
            n = len(s)
            og = [r["oracle_gain"] for r in s]
            pg = [r["pick_one_gain"] for r in s]
            si = [r["switch_increment"] for r in s]
            cr = [r["causal_regret"] for r in s]
            healthy = [r for r in s if r["center"] > 0.0]
            print(f"\n--- {scale} | {metric}  (n={n}) ---")
            print(f"  oracle_gain      median={med(og):+.5f}  >0.01: {sum(x>0.01 for x in og)}/{n}")
            print(f"  pick_one_gain    median={med(pg):+.5f}  >0.01: {sum(x>0.01 for x in pg)}/{n}")
            print(f"  switch_increment median={med(si):+.5f}  >0.01: {sum(x>0.01 for x in si)}/{n}")
            print(f"  causal_regret    median={med(cr):+.5f}  (vs best fixed; >=0 is a loss)")
            print(f"  basins that ever switch: {sum(1 for r in s if r['n_segments_switched']>0)}/{n}"
                  f"   median segs switched: {med([r['n_segments_switched'] for r in s]):.1f}"
                  f" of {med([float(r['n_segments']) for r in s]):.0f}")
            print(f"  ROBUSTNESS center_nse>0 only (n={len(healthy)}): "
                  f"oracle_gain median={med([r['oracle_gain'] for r in healthy]):+.5f}"
                  f"  switch_increment median={med([r['switch_increment'] for r in healthy]):+.5f}")
            print(f"  center NSE: min={min(r['center'] for r in s):+.3f} "
                  f"median={med([r['center'] for r in s]):+.3f}  n_negative={sum(1 for r in s if r['center']<0)}")
            print(f"  candidate_collapse: {sum(1 for r in s if r['candidate_collapse']=='True')}/{n}"
                  f"   clipped_any: {sum(1 for r in s if r['clipped_any']=='True')}/{n}")
    # worst probe-vs-table diagnostics
    rep = list(csv.DictReader(open(ROOT / f"out/calibration_reproduction_{window}.csv")))
    for r in rep: r["abs_diff"] = float(r["abs_diff"]); r["center_nse_recomputed"]=float(r["center_nse_recomputed"])
    rep.sort(key=lambda r: -r["abs_diff"])
    print("\n  worst probe-window center vs table _cal_nse (different warmups by design):")
    for r in rep[:4]:
        print(f"    {r['basin_id']}  probe={r['center_nse_recomputed']:+.4f} "
              f"table={r['cal_nse_table']}  |diff|={r['abs_diff']:.4f}")
PY
