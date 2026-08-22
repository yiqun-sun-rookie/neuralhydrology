#!/bin/bash
# nature1st-attr-swap seq=77 -- armG watchdog, unattended routine re-check. READ-ONLY, no sbatch, no resubmit.
# Job 207826 = q_armG_china_supplyable. Previous check (seq=76, 20:29 CST): COMPLETED 09:55:16 on ngu007,
# guard confirmed 17 attributes, best epoch 16 median 0.6299, verdict INCONCLUSIVE vs armC.
# This round re-confirms the terminal state is unchanged, re-derives every paired statistic from the raw
# per-station CSVs, and checks whether any seed 43/44 follow-up job has appeared in the queue since.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
J=207826
cd "$RUN" || { echo RUN_DIR_MISSING; exit 1; }

echo "=== A. STATE ==="
date '+wallclock now: %Y-%m-%d %H:%M:%S %z'
squeue -j $J -o '%.10i %.28j %.10T %.10M %.24R' 2>&1 | head -5
sacct -j $J -X --format=JobID%10,JobName%26,State%12,ExitCode%8,Elapsed%12,NodeList%9 2>&1 | head -5

echo "=== A2. ANY ATTR-SWAP / SEED 43-44 JOBS IN QUEUE ==="
squeue -u sunyiq -o '%.10i %.28j %.10T %.10M %.20R' 2>&1 | head -14

echo "=== B. GUARD (must say 17 attributes) ==="
f=logs/attr_swap/armG_china_supplyable-${J}.out
e=logs/attr_swap/armG_china_supplyable-${J}.err
if [ ! -f "$f" ]; then
  echo "(no stdout log -- job never started?)"
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
  echo "-- artifact timestamps --"
  stat -c '%y  %s bytes  %n' models/q_lstm_armG_hpc_s42/best_metrics.json 2>/dev/null || true
  stat -c '%y  %s bytes  %n' models/q_lstm_armG_hpc_s42/eval_val_per_station.csv 2>/dev/null || true
else
  echo "best_metrics.json not present"
fi

echo "=== E. PAIRED VERDICT ==="
G=models/q_lstm_armG_hpc_s42/eval_val_per_station.csv
if [ ! -f "$G" ]; then
  echo "armG per-station scores not written -- nothing to judge"
else
  source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null || true
  conda activate nh_final 2>/dev/null || true
  python - <<'PY' 2>&1 | head -140
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

summary = {}
for ref in ["armC", "armF", "control"]:
    r = data[ref]
    print("")
    print(f"---------- armG vs {ref} ----------")
    if r is None:
        print(f"{ref} per-station csv missing -- skipped")
        continue
    m = g.merge(r, on="station", suffixes=("_g", "_r"))
    n = len(m)
    if n == 0:
        print("no overlapping stations")
        continue
    d = (m["nse_g"] - m["nse_r"]).to_numpy(dtype=float)
    lo, hi = boot_median_ci(d)
    med_g = float(m["nse_g"].median())
    med_r = float(m["nse_r"].median())
    worse = int((d < 0).sum())
    better = int((d > 0).sum())
    drop10 = float((d < -0.10).mean())
    gain10 = float((d > 0.10).mean())
    pmd = float(np.median(d))
    summary[ref] = (pmd, drop10 * 100.0)
    print(f"paired n            = {n}")
    print(f"median armG         = {med_g:.4f}")
    print(f"median {ref:11s} = {med_r:.4f}")
    print(f"group median diff   = {med_g - med_r:+.4f}")
    print(f"PAIRED median diff  = {pmd:+.4f}   95% CI [{lo:+.4f}, {hi:+.4f}]")
    print(f"worse / better      = {worse} / {better}")
    print(f"frac drop > 0.10    = {drop10*100:.1f}%")
    print(f"frac gain > 0.10    = {gain10*100:.1f}%")
    scol = "stratum_g" if "stratum_g" in m.columns else ("stratum" if "stratum" in m.columns else None)
    if scol:
        print("by stratum (paired median diff, n):")
        for s, sub in m.groupby(scol):
            sd = (sub["nse_g"] - sub["nse_r"]).to_numpy(dtype=float)
            print(f"   {str(s):22s} {float(np.median(sd)):+.4f}  n={len(sd)}")

print("")
print("---------- PRE-REGISTERED DECISION vs armC ----------")
if "armC" in summary:
    pmd, dr = summary["armC"]
    print(f"paired median diff = {pmd:+.4f}   frac drop>0.10 = {dr:.1f}%")
    print(f"  rule SUFFICIENT : pmd >= -0.010 AND drop <= 20%  -> {pmd >= -0.010 and dr <= 20.0}")
    print(f"  rule VETO       : pmd <  -0.030 OR  drop >  35%  -> {pmd < -0.030 or dr > 35.0}")
    if pmd >= -0.010 and dr <= 20.0:
        print("VERDICT: SUFFICIENT")
    elif pmd < -0.030 or dr > 35.0:
        print("VERDICT: VETO")
    else:
        print("VERDICT: INCONCLUSIVE -- needs seeds 43/44, no single-seed conclusion allowed")
else:
    print("armC missing -- cannot decide")
PY
fi
echo "=== END seq=77 ==="
