#!/bin/bash
# nature1st-attr-swap -- STATUS ONLY, supersedes the arm E/F submit command.
# NO sbatch anywhere: a daemon restart re-scans this channel, and a leftover submit
# command would launch duplicate jobs.
#   206718 arm E   4 attributes = the winning 8 minus the 4 the global set cannot rebuild
#   206719 arm F  17 attributes = the 13 global plus those same 4 (same count as arm D)
# Finished arms: control 0.6432 / global 0.5983 / armC 0.6466 / armD 0.6059.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
E=206718
F=206719

echo "=== A. JOB STATE ==="
sacct -j $E,$F -X --format=JobID%10,JobName%26,State%12,ExitCode%8,Elapsed%12,NodeList%9 2>&1

echo "=== A2. QUEUE REASON (why still pending?) ==="
squeue -j $E,$F -o "%.10i %.24j %.10T %.10M %.20R %.12Q" 2>&1 | head -5
echo "-- partition hgpu2p occupancy --"
squeue -p hgpu2p -o "%.10i %.10u %.10T %.12M %.20R" 2>&1 | head -12
sinfo -p hgpu2p -o "%.12P %.6a %.10l %.6D %.6t %N" 2>&1 | head -6

echo "=== B. PROGRESS ==="
for tag in "armE:armE_minus4:$E" "armF:armF_plus4:$F"; do
    name=${tag%%:*}; rest=${tag#*:}; pre=${rest%%:*}; jid=${rest##*:}
    f=$(ls "$RUN"/logs/attr_swap/${pre}-${jid}.out 2>/dev/null | head -1)
    echo "--- $name ($jid) ---"
    if [ -n "$f" ]; then
        grep -E '\[guard\]|val_median_NSE|Best median NSE|early stop|Done\.' "$f" 2>/dev/null | tail -6 || true
    else
        echo "(no log yet -- still queued?)"
    fi
done

echo "=== B2. EPOCH-MATCHED TRAJECTORY ==="
python - <<'PY' 2>&1
import json, os
R = "/data1/home/sunyiq/nature_1st/models"
ARMS = [("control", "q_lstm_control_hpc_s42"), ("global", "q_lstm_hydroatlas_hpc_s42"),
        ("armC", "q_lstm_usminus4_hpc_s42"), ("armD", "q_lstm_globalplus4_hpc_s42"),
        ("armE", "q_lstm_armE_hpc_s42"), ("armF", "q_lstm_armF_hpc_s42")]
hist = {}
for lab, d in ARMS:
    p = os.path.join(R, d, "train_history.jsonl")
    if not os.path.exists(p):
        continue
    rows = []
    for line in open(p):
        line = line.strip()
        if line:
            try:
                rows.append(json.loads(line))
            except Exception:
                pass
    if rows:
        hist[lab] = rows
if not hist:
    print("(no train_history.jsonl found)")
else:
    def nse(r):
        for k in ("val_median_nse", "median_nse", "val_median_NSE", "nse"):
            if k in r:
                return r[k]
        return (r.get("val") or {}).get("median_nse")
    labs = [l for l, _ in ARMS if l in hist]
    n = max(len(hist[l]) for l in labs)
    print("epoch  " + "  ".join(f"{l:>8}" for l in labs))
    for i in range(n):
        cells = []
        for l in labs:
            v = nse(hist[l][i]) if i < len(hist[l]) else None
            cells.append(f"{v:>8.4f}" if isinstance(v, (int, float)) else f"{'-':>8}")
        print(f"{i+1:>5}  " + "  ".join(cells))
    print("best   " + "  ".join(
        f"{max([x for x in (nse(r) for r in hist[l]) if isinstance(x,(int,float))] or [float('nan')]):>8.4f}"
        for l in labs))
    print("epochs " + "  ".join(f"{len(hist[l]):>8}" for l in labs))
PY

echo "=== C. PAIRED ANALYSIS (same procedure as every verdict in this campaign) ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python - <<'PY' 2>&1
import os
import numpy as np, pandas as pd
R = "/data1/home/sunyiq/nature_1st/models"
P = {"control": "q_lstm_control_hpc_s42", "global": "q_lstm_hydroatlas_hpc_s42",
     "armC": "q_lstm_usminus4_hpc_s42", "armD": "q_lstm_globalplus4_hpc_s42",
     "armE": "q_lstm_armE_hpc_s42", "armF": "q_lstm_armF_hpc_s42"}


def load(k):
    p = os.path.join(R, P[k], "eval_val_per_station.csv")
    return pd.read_csv(p).set_index("station") if os.path.exists(p) else None


def paired(la, lb, note):
    a, b = load(la), load(lb)
    if a is None or b is None:
        print(f"[{lb} vs {la}] not ready yet")
        return
    j = b[["nse", "stratum"]].join(a[["nse"]], lsuffix="_b", rsuffix="_a").dropna(
        subset=["nse_b", "nse_a"])
    d = (j.nse_b - j.nse_a).values
    rng = np.random.default_rng(0)
    bs = [np.median(rng.choice(d, len(d), replace=True)) for _ in range(5000)]
    print(f"[{lb} vs {la}]  {note}")
    print(f"  n={len(j)}  {la} median {j.nse_a.median():.4f}   {lb} median {j.nse_b.median():.4f}")
    print(f"  group median diff   {j.nse_b.median()-j.nse_a.median():+.4f}")
    print(f"  PAIRED median diff  {np.median(d):+.4f}   "
          f"95%CI [{np.percentile(bs,2.5):+.4f}, {np.percentile(bs,97.5):+.4f}]")
    print(f"  worse/better {(d<0).sum()}/{(d>0).sum()}  ({(d<0).mean()*100:.1f}% worse)   "
          f"lost>0.10 {(d<-0.10).mean()*100:.1f}%  gained>0.10 {(d>0.10).mean()*100:.1f}%")
    try:
        from scipy.stats import wilcoxon
        print(f"  wilcoxon p          {wilcoxon(j.nse_b, j.nse_a)[1]:.3e}")
    except Exception as e:
        print("  wilcoxon unavailable:", e)
    for s, g in j.groupby("stratum"):
        print(f"    {s:<12} n={len(g):>3}  paired {np.median((g.nse_b-g.nse_a).values):+.4f}")


paired("armC", "armE", "subtraction: <= -0.020 those 4 carry the information; >= -0.010 they do not")
paired("global", "armF", "addition (decisive): >= +0.020 repairs; <= +0.010 does not")
paired("armD", "armF", "COUNT-CONTROLLED: both arms have 17 attributes, only identity differs")
paired("control", "armF", "context: how much of the US 12 is recovered")
PY

echo "=== END status round ==="
