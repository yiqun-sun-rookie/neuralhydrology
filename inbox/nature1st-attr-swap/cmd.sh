#!/bin/bash
# nature1st-attr-swap -- STATUS ONLY for the stream-network ablation.
# NO sbatch anywhere: a daemon restart re-scans this channel, and a leftover submit
# command would launch duplicate jobs.
#   206409 arm C  8 US attributes (12 minus the 4 network ones)
#   206410 arm D  17 attributes (13 HydroATLAS + the 4 network ones)
# Reference arms already finished: 206175 control 0.6432 / 206176 global 0.5983.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
C=206409
D=206410

echo "=== A. JOB STATE ==="
sacct -j $C,$D -X --format=JobID%10,JobName%24,State%12,ExitCode%8,Elapsed%12,NodeList%9 2>&1

echo "=== B. PROGRESS ==="
for tag in "armC:$C" "armD:$D"; do
    name=${tag%%:*}; jid=${tag##*:}
    f=$(ls "$RUN"/logs/attr_swap/${name}_*-${jid}.out 2>/dev/null | head -1)
    echo "--- $name ($jid) ---"
    if [ -n "$f" ]; then
        grep -E 'val_median_NSE|Best median NSE|early stop|Done\.' "$f" 2>/dev/null | tail -6 || true
    else
        echo "(no log yet)"
    fi
done

echo "=== B2. EPOCH-MATCHED TRAJECTORY (the only fair mid-run read) ==="
python - <<'PY' 2>&1
import json, os
R = "/data1/home/sunyiq/nature_1st/models"
ARMS = [("control", "q_lstm_control_hpc_s42"), ("global", "q_lstm_hydroatlas_hpc_s42"),
        ("armC", "q_lstm_usminus4_hpc_s42"), ("armD", "q_lstm_globalplus4_hpc_s42")]
hist = {}
for lab, d in ARMS:
    p = os.path.join(R, d, "train_history.jsonl")
    if not os.path.exists(p):
        continue
    rows = []
    for line in open(p):
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except Exception:
            pass
    hist[lab] = rows
if not hist:
    print("(no train_history.jsonl found)")
else:
    def nse(r):
        for k in ("val_median_nse", "median_nse", "val_median_NSE", "nse"):
            if k in r:
                return r[k]
        v = r.get("val") or {}
        return v.get("median_nse")
    n = max(len(v) for v in hist.values())
    labs = [l for l, _ in ARMS if l in hist]
    print("epoch  " + "  ".join(f"{l:>8}" for l in labs))
    for i in range(n):
        cells = []
        for l in labs:
            r = hist[l][i] if i < len(hist[l]) else None
            v = nse(r) if r else None
            cells.append(f"{v:>8.4f}" if isinstance(v, (int, float)) else f"{'-':>8}")
        print(f"{i+1:>5}  " + "  ".join(cells))
    print("best   " + "  ".join(
        f"{max([x for x in (nse(r) for r in hist[l]) if isinstance(x,(int,float))] or [float('nan')]):>8.4f}"
        for l in labs))
    print("epochs " + "  ".join(f"{len(hist[l]):>8}" for l in labs))
PY

echo "=== C. EVAL ARTIFACTS ==="
for d in q_lstm_usminus4_hpc_s42 q_lstm_globalplus4_hpc_s42; do
    echo "--- $d ---"
    ls -la "$RUN/models/$d"/best_metrics.json "$RUN/models/$d"/eval_val_per_station.csv 2>&1 | head -3
done

echo "=== D. PAIRED ANALYSIS (same procedure as the 2026-08-20 verdict) ==="
CTRL="$RUN/models/q_lstm_control_hpc_s42/eval_val_per_station.csv"
GLOB="$RUN/models/q_lstm_hydroatlas_hpc_s42/eval_val_per_station.csv"
ARMC="$RUN/models/q_lstm_usminus4_hpc_s42/eval_val_per_station.csv"
ARMD="$RUN/models/q_lstm_globalplus4_hpc_s42/eval_val_per_station.csv"
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python - "$CTRL" "$GLOB" "$ARMC" "$ARMD" <<'PY' 2>&1
import os, sys
import numpy as np, pandas as pd

ctrl, glob_, armc, armd = sys.argv[1:5]


def load(p):
    return pd.read_csv(p).set_index("station") if os.path.exists(p) else None


CT, GL, C, D = load(ctrl), load(glob_), load(armc), load(armd)


def paired(a, b, la, lb, note):
    """b minus a, per station."""
    if a is None or b is None:
        print(f"[{lb} vs {la}] not ready yet")
        return
    j = b[["nse", "stratum"]].join(a[["nse"]], lsuffix="_b", rsuffix="_a").dropna(
        subset=["nse_b", "nse_a"])
    d = (j.nse_b - j.nse_a).values
    rng = np.random.default_rng(0)
    bs = [np.median(rng.choice(d, len(d), replace=True)) for _ in range(5000)]
    print(f"[{lb} vs {la}]  {note}")
    print(f"  paired stations     {len(j)}")
    print(f"  {la:<10} median      {j.nse_a.median():.4f}")
    print(f"  {lb:<10} median      {j.nse_b.median():.4f}")
    print(f"  group median diff   {j.nse_b.median()-j.nse_a.median():+.4f}")
    print(f"  PAIRED median diff  {np.median(d):+.4f}   "
          f"95%CI [{np.percentile(bs,2.5):+.4f}, {np.percentile(bs,97.5):+.4f}]")
    print(f"  worse / better      {(d<0).sum()} / {(d>0).sum()}  ({(d<0).mean()*100:.1f}% worse)")
    print(f"  lost>0.10 {(d<-0.10).mean()*100:.1f}%   gained>0.10 {(d>0.10).mean()*100:.1f}%")
    try:
        from scipy.stats import wilcoxon
        print(f"  wilcoxon p          {wilcoxon(j.nse_b, j.nse_a)[1]:.3e}")
    except Exception as e:
        print("  wilcoxon unavailable:", e)
    print("  -- by stratum (paired) --")
    for s, g in j.groupby("stratum"):
        print(f"    {s:<12} n={len(g):>3}  paired {np.median((g.nse_b-g.nse_a).values):+.4f}")


paired(CT, C, "control", "armC",
       "subtraction: <= -0.020 network attrs carry information; >= -0.010 hypothesis dead")
paired(GL, D, "global", "armD",
       "addition (decisive): >= +0.020 they repair the gap; <= +0.010 hypothesis dead")
paired(CT, D, "control", "armD", "context only: 17 attrs vs the US 12")
PY

echo "=== END status round ==="
