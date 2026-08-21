#!/bin/bash
# nature1st-attr-swap seq=70 -- armG watchdog. READ-ONLY, no sbatch, no resubmit.
# Job 207826 = q_armG_china_supplyable, submitted 2026-08-21 17:05, 40-epoch cap, patience 5.
# Reference wall time: armE 3h02 (12 epochs), armF 6h06 (25 epochs).
# Previous check (seq=69, 23:32): RUNNING 5:45, epoch 12, guard confirmed 17 attributes.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
J=207826
cd "$RUN" || { echo RUN_DIR_MISSING; exit 1; }

echo "=== A. STATE ==="
date '+wallclock now: %Y-%m-%d %H:%M:%S %z'
squeue -j $J -o '%.10i %.28j %.10T %.10M %.24R' 2>&1 | head -5
sacct -j $J -X --format=JobID%10,JobName%26,State%12,ExitCode%8,Elapsed%12,NodeList%9 2>&1 | head -5

echo "=== B. GUARD (must say 17 attributes) ==="
f=logs/attr_swap/armG_china_supplyable-${J}.out
e=logs/attr_swap/armG_china_supplyable-${J}.err
if [ ! -f "$f" ]; then
  echo "(no stdout log yet -- still pending)"
else
  grep -E "\[guard\]" "$f" 2>/dev/null | head -4 || true
fi

echo "=== B2. ERRORS ==="
for g in "$f" "$e"; do
  if [ -f "$g" ]; then
    echo "-- $g --"
    grep -E "RuntimeError|Traceback|CUDA|FATAL|refusing" "$g" 2>/dev/null | head -8 || true
  fi
done

echo "=== C. PROGRESS ==="
if [ -f "$f" ]; then
  echo "log bytes: $(stat -c%s "$f")  last touched: $(stat -c%y "$f" | cut -c1-19)"
  grep -E "^Epoch|Best val median NSE|Done\." "$f" 2>/dev/null | tail -8 || true
fi

echo "=== D. FINISHED? ==="
if [ -f models/q_lstm_armG_hpc_s42/best_metrics.json ]; then
  cat models/q_lstm_armG_hpc_s42/best_metrics.json 2>&1
  echo ""
else
  echo "best_metrics.json not present yet"
fi

echo "=== E. PAIRED VERDICT (only runs once armG eval_val_per_station.csv exists) ==="
G=models/q_lstm_armG_hpc_s42/eval_val_per_station.csv
if [ ! -f "$G" ]; then
  echo "armG per-station scores not written yet -- nothing to judge"
else
  source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null || true
  conda activate nh_final 2>/dev/null || true
  python - <<'PY' 2>&1 | head -120
import os
import numpy as np
import pandas as pd

BASE = "models"
ARMS = {
    "armG":    "q_lstm_armG_hpc_s42",
    "armC":    "q_lstm_usminus4_hpc_s42",
    "armF":    "q_lstm_armF_hpc_s42",
    "control": "q_lstm_control_hpc_s42",
}

def load(d):
    p = os.path.join(BASE, d, "eval_val_per_station.csv")
    if not os.path.exists(p):
        return None
    df = pd.read_csv(p)
    df["station"] = df["station"].astype(str)
    keep = ["station", "nse"] + (["stratum"] if "stratum" in df.columns else [])
    return df[keep].dropna(subset=["nse"]).drop_duplicates("station")

data = {k: load(v) for k, v in ARMS.items()}
for k, v in data.items():
    print(f"{k:8s} rows={0 if v is None else len(v)}  median={float('nan') if v is None else round(float(v['nse'].median()),4)}")

g = data["armG"]
if g is None:
    print("armG csv unreadable")
    raise SystemExit(0)

rng = np.random.default_rng(0)

def boot_median_ci(d, n=5000):
    d = np.asarray(d, dtype=float)
    idx = rng.integers(0, len(d), size=(n, len(d)))
    meds = np.median(d[idx], axis=1)
    return float(np.percentile(meds, 2.5)), float(np.percentile(meds, 97.5))

for ref in ["armC", "armF", "control"]:
    r = data[ref]
    print("")
    print(f"---------- armG vs {ref} ----------")
    if r is None:
        print(f"{ref} per-station csv missing -- skipped")
        continue
    m = g.merge(r, on="station", suffixes=("_g", "_r"))
    n = len(m)
    d = (m["nse_g"] - m["nse_r"]).to_numpy(dtype=float)
    if n == 0:
        print("no overlapping stations")
        continue
    lo, hi = boot_median_ci(d)
    med_g = float(m["nse_g"].median())
    med_r = float(m["nse_r"].median())
    worse = int((d < 0).sum())
    better = int((d > 0).sum())
    drop10 = float((d < -0.10).mean())
    gain10 = float((d > 0.10).mean())
    print(f"paired n            = {n}")
    print(f"median armG         = {med_g:.4f}")
    print(f"median {ref:11s} = {med_r:.4f}")
    print(f"group median diff   = {med_g - med_r:+.4f}")
    print(f"PAIRED median diff  = {float(np.median(d)):+.4f}   95% CI [{lo:+.4f}, {hi:+.4f}]")
    print(f"worse / better      = {worse} / {better}")
    print(f"frac drop > 0.10    = {drop10*100:.1f}%")
    print(f"frac gain > 0.10    = {gain10*100:.1f}%")
    scol = "stratum_g" if "stratum_g" in m.columns else ("stratum" if "stratum" in m.columns else None)
    if scol:
        print("by stratum (paired median diff, n):")
        for s, sub in m.groupby(scol):
            dd = (sub["nse_g"] - sub["nse_r"]).to_numpy(dtype=float)
            print(f"   {str(s):24s} {float(np.median(dd)):+.4f}  n={len(dd)}")

print("")
print("---------- PRE-REGISTERED DECISION vs armC ----------")
r = data["armC"]
if r is None:
    print("armC missing -- cannot apply criterion")
else:
    m = g.merge(r, on="station", suffixes=("_g", "_r"))
    d = (m["nse_g"] - m["nse_r"]).to_numpy(dtype=float)
    pm = float(np.median(d))
    dr = float((d < -0.10).mean())
    if pm >= -0.010 and dr <= 0.20:
        v = "SUFFICIENT (paired median >= -0.010 AND drop>0.10 frac <= 20%)"
    elif pm < -0.030 or dr > 0.35:
        v = "REJECTED (paired median < -0.030 OR drop>0.10 frac > 35%)"
    else:
        v = "INCONCLUSIVE -- needs seeds 43/44, no single-seed conclusion allowed"
    print(f"paired median diff = {pm:+.4f}   frac drop>0.10 = {dr*100:.1f}%")
    print(f"VERDICT: {v}")
PY
fi

echo "=== END seq=70 ==="
