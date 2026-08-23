#!/bin/bash
# nature1st-attr-swap seq=83 -- armG (job 207826) unattended watchdog. READ-ONLY. No sbatch, no resubmit.
# Independent re-check of the terminal state and full re-derivation of the paired statistics from the raw
# per-station CSVs, plus a check for any seed 43/44 follow-up that may have appeared since seq=82.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
J=207826
cd "$RUN" || { echo RUN_DIR_MISSING; exit 1; }

echo "=== A. STATE ==="
date '+wallclock now: %Y-%m-%d %H:%M:%S %z'
squeue -j $J -o '%.10i %.28j %.10T %.10M %.24R' 2>&1 | head -5
sacct -j $J -X --format=JobID%10,JobName%26,State%12,ExitCode%8,Elapsed%12,NodeList%9 2>&1 | head -5

echo "=== A2. OWN QUEUE (looking for armG seed 43/44) ==="
squeue -u sunyiq -o '%.10i %.28j %.10T %.10M %.20R' 2>&1 | head -14

echo "=== B. GUARD (must say 17 attributes) ==="
LOG="$RUN/logs/attr_swap/armG_china_supplyable-207826.out"
ERR="$RUN/logs/attr_swap/armG_china_supplyable-207826.err"
if [ -f "$LOG" ]; then
  grep '\[guard\]' "$LOG" | head -6 || true
else
  echo "OUT LOG MISSING: $LOG"
fi

echo "=== B2. ERRORS ==="
for f in "$LOG" "$ERR"; do
  echo "-- $f --"
  if [ -f "$f" ]; then
    grep -E 'RuntimeError|Traceback|CUDA|FATAL|refusing' "$f" | head -12 || true
  else
    echo "(missing)"
  fi
done

echo "=== C. PROGRESS ==="
if [ -f "$LOG" ]; then
  echo "out log bytes: $(stat -c%s "$LOG" 2>/dev/null)  last touched: $(stat -c%y "$LOG" 2>/dev/null)"
  grep -E '^Epoch|Best val median NSE|Done\.' "$LOG" | tail -8 || true
fi

echo "=== D. FINISHED? ==="
BM="$RUN/models/q_lstm_armG_hpc_s42/best_metrics.json"
if [ -f "$BM" ]; then cat "$BM"; else echo "best_metrics.json ABSENT"; fi
echo "-- artifact timestamps --"
for f in "$RUN/models/q_lstm_armG_hpc_s42/best_metrics.json" "$RUN/models/q_lstm_armG_hpc_s42/eval_val_per_station.csv"; do
  [ -f "$f" ] && stat -c '%y  %s bytes  %n' "$f" || echo "(absent) $f"
done

echo "=== E. PAIRED VERDICT ==="
CSV="$RUN/models/q_lstm_armG_hpc_s42/eval_val_per_station.csv"
if [ -f "$CSV" ]; then
  source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
  conda activate nh_final 2>/dev/null
  python - <<'PYEOF' 2>&1 | head -120
import os
import numpy as np
import pandas as pd

RUN = "/data1/home/sunyiq/nature_1st"
DIRS = {
    "armG":    "q_lstm_armG_hpc_s42",
    "armC":    "q_lstm_usminus4_hpc_s42",
    "armF":    "q_lstm_armF_hpc_s42",
    "control": "q_lstm_control_hpc_s42",
}

def load(d):
    p = os.path.join(RUN, "models", d, "eval_val_per_station.csv")
    if not os.path.exists(p):
        return None
    df = pd.read_csv(p)
    df = df[["station", "nse", "stratum"]].copy()
    df["station"] = df["station"].astype(str)
    return df.drop_duplicates("station").set_index("station")

data = {k: load(v) for k, v in DIRS.items()}
for k, v in data.items():
    if v is None:
        print("MISSING per-station csv for %s (%s)" % (k, DIRS[k]))
    else:
        print("%-8s rows=%d  median=%.4f" % (k, len(v), v["nse"].median()))

g = data["armG"]
if g is None:
    raise SystemExit("armG csv missing -- cannot compare")

rng = np.random.default_rng(0)

def compare(name):
    o = data[name]
    if o is None:
        print("\n---------- armG vs %s : SKIPPED (csv missing) ----------" % name)
        return None
    j = g.join(o, how="inner", lsuffix="_g", rsuffix="_o")
    d = (j["nse_g"] - j["nse_o"]).to_numpy()
    n = len(d)
    pmd = float(np.median(d))
    boot = np.array([np.median(d[rng.integers(0, n, n)]) for _ in range(5000)])
    lo, hi = np.percentile(boot, [2.5, 97.5])
    worse = int((d < 0).sum()); better = int((d > 0).sum())
    fdrop = float((d < -0.10).mean()) * 100.0
    fgain = float((d > 0.10).mean()) * 100.0
    print("\n---------- armG vs %s ----------" % name)
    print("paired n            = %d" % n)
    print("median armG         = %.4f" % j["nse_g"].median())
    print("median %-12s= %.4f" % (name, j["nse_o"].median()))
    print("group median diff   = %+.4f" % (j["nse_g"].median() - j["nse_o"].median()))
    print("PAIRED median diff  = %+.4f   95%% CI [%+.4f, %+.4f]" % (pmd, lo, hi))
    print("worse / better      = %d / %d" % (worse, better))
    print("frac drop > 0.10    = %.1f%%" % fdrop)
    print("frac gain > 0.10    = %.1f%%" % fgain)
    print("by stratum (paired median diff, n):")
    st = j["stratum_g"] if "stratum_g" in j.columns else j["stratum"]
    for s, idx in j.groupby(st).groups.items():
        dd = (j.loc[idx, "nse_g"] - j.loc[idx, "nse_o"]).to_numpy()
        print("   %-20s %+.4f  n=%d" % (s, float(np.median(dd)), len(dd)))
    return pmd, fdrop

res = {}
for nm in ("armC", "armF", "control"):
    r = compare(nm)
    if r:
        res[nm] = r

print("\n---------- PRE-REGISTERED DECISION vs armC ----------")
if "armC" in res:
    pmd, fdrop = res["armC"]
    suff = (pmd >= -0.010) and (fdrop <= 20.0)
    veto = (pmd < -0.030) or (fdrop > 35.0)
    print("paired median diff = %+.4f   frac drop>0.10 = %.1f%%" % (pmd, fdrop))
    print("  rule SUFFICIENT : pmd >= -0.010 AND drop <= 20%%  -> %s" % suff)
    print("  rule VETO       : pmd <  -0.030 OR  drop >  35%%  -> %s" % veto)
    if suff:
        print("VERDICT: SUFFICIENT")
    elif veto:
        print("VERDICT: VETO")
    else:
        print("VERDICT: INCONCLUSIVE -- needs seeds 43/44, no single-seed conclusion allowed")
else:
    print("armC csv missing -- cannot apply pre-registered rule")
PYEOF
else
  echo "eval_val_per_station.csv ABSENT -- no paired comparison possible"
fi

echo "=== F. SEED 43/44 FOLLOW-UP PRESENT? ==="
for s in 43 44; do
  D="$RUN/models/q_lstm_armG_hpc_s$s"
  if [ -d "$D" ]; then
    echo "-- $D EXISTS --"
    if [ -f "$D/best_metrics.json" ]; then cat "$D/best_metrics.json" | head -14; else echo "   (no best_metrics.json yet)"; fi
  else
    echo "-- models/q_lstm_armG_hpc_s$s absent --"
  fi
done

echo "=== END seq=83 ==="
