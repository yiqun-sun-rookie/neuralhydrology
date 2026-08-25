#!/bin/bash
# nature1st-attr-swap seq=96 -- READ-ONLY watchdog for armI (job 211317). NO sbatch, NO compute.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
J=211317
cd "$RUN" || { echo RUN_DIR_MISSING; exit 1; }
date "+wallclock %F %T %z"
echo "=== A. STATE ==="
squeue -j $J -o '%.10i %.24j %.10T %.10M %.22R' 2>&1
sacct -j $J -X --format=JobID%10,JobName%22,State%12,ExitCode%8,Elapsed%11,NodeList%9 2>&1

echo "=== B. GUARD (must say 16 attributes) ==="
f=logs/attr_swap/armI_no_neardam-${J}.out
e=logs/attr_swap/armI_no_neardam-${J}.err
if [ ! -f "$f" ]; then echo "(no stdout log)"; else
  grep -E "\[guard\]" "$f" 2>/dev/null | head -4 || true
  echo "log bytes: $(stat -c%s "$f")  last touched: $(stat -c%y "$f" | cut -c1-19)"
fi

echo "=== C. ERRORS ==="
for g in "$f" "$e"; do [ -f "$g" ] && { echo "-- $g ($(stat -c%s "$g") bytes, touched $(stat -c%y "$g" | cut -c1-19)) --"; grep -E "RuntimeError|Traceback|CUDA|FATAL|Killed|out of memory" "$g" 2>/dev/null | head -10 || true; }; done

echo "=== D. PROGRESS ==="
[ -f "$f" ] && { grep -E "^Epoch|Best val median NSE|Done\." "$f" 2>/dev/null | tail -10 || true; }

echo "=== E. RESULT? (best-so-far if still running) ==="
if [ -f models/q_lstm_armI_hpc_s42/best_metrics.json ]; then cat models/q_lstm_armI_hpc_s42/best_metrics.json 2>&1; echo; else echo '(no best_metrics.json)'; fi
ls -la models/q_lstm_armI_hpc_s42/eval_val_per_station.csv 2>&1 | head -2

echo "=== F. WHOLE CAMPAIGN ROLL CALL ==="
for d in q_lstm_control_hpc_s42 q_lstm_hydroatlas_hpc_s42 q_lstm_usminus4_hpc_s42 \
         q_lstm_globalplus4_hpc_s42 q_lstm_armE_hpc_s42 q_lstm_armF_hpc_s42 \
         q_lstm_armG_hpc_s42 q_lstm_armI_hpc_s42 ; do
  if [ -f models/$d/best_metrics.json ]; then
    m=$(python -c "import json,sys;print(f'{json.load(open(sys.argv[1]))[\"median_nse\"]:.4f}')" models/$d/best_metrics.json 2>/dev/null)
    printf '  %-30s %s\n' "$d" "$m"
  else printf '  %-30s (running or absent)\n' "$d"; fi
done

echo "=== G. PAIRED ANALYSIS (only if armI eval csv exists) ==="
if [ -f models/q_lstm_armI_hpc_s42/eval_val_per_station.csv ]; then
  source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null || true
  conda activate nh_final 2>/dev/null || true
  python - <<'PYEOF' 2>&1
import os
import numpy as np, pandas as pd

BASE = "models"
def load(tag):
    p = os.path.join(BASE, tag, "eval_val_per_station.csv")
    if not os.path.exists(p):
        return None
    d = pd.read_csv(p)
    cols = {c.lower(): c for c in d.columns}
    s = cols.get("station"); n = cols.get("nse"); st = cols.get("stratum")
    if s is None or n is None:
        print(f"  !! {tag}: unexpected columns {list(d.columns)}")
        return None
    out = d[[s, n] + ([st] if st else [])].copy()
    out.columns = ["station", "nse"] + (["stratum"] if st else [])
    if st is None:
        out["stratum"] = "ALL"
    return out.drop_duplicates("station")

REF = load("q_lstm_armI_hpc_s42")
if REF is None:
    print("armI csv unreadable")
else:
    print(f"armI stations={len(REF)}  median={REF.nse.median():.4f}")
    rng = np.random.default_rng(0)
    for name, tag in [("armF", "q_lstm_armF_hpc_s42"),
                      ("armG", "q_lstm_armG_hpc_s42"),
                      ("armC", "q_lstm_usminus4_hpc_s42")]:
        O = load(tag)
        if O is None:
            print(f"\n--- armI vs {name}: csv missing ---")
            continue
        m = REF.merge(O[["station", "nse"]], on="station", suffixes=("_I", "_O"))
        d = (m.nse_I - m.nse_O).values
        n = len(d)
        pm = float(np.median(d))
        boot = np.array([np.median(rng.choice(d, n, replace=True)) for _ in range(5000)])
        lo, hi = np.percentile(boot, [2.5, 97.5])
        print(f"\n--- armI vs {name}  (n={n} paired) ---")
        print(f"  median armI = {m.nse_I.median():.4f}   median {name} = {m.nse_O.median():.4f}"
              f"   group-median diff = {m.nse_I.median()-m.nse_O.median():+.4f}")
        print(f"  PAIRED median diff = {pm:+.4f}   95% CI [{lo:+.4f}, {hi:+.4f}]")
        print(f"  worse={int((d<0).sum())}  better={int((d>0).sum())}"
              f"   drop>0.10: {100*(d<-0.10).mean():.1f}%   gain>0.10: {100*(d>0.10).mean():.1f}%")
        if "stratum" in m.columns or "stratum" in REF.columns:
            mm = m.copy()
            mm["stratum"] = REF.set_index("station").loc[mm.station, "stratum"].values
            mm["d"] = mm.nse_I - mm.nse_O
            print("  by stratum (paired median diff, n):")
            for k, g in mm.groupby("stratum"):
                print(f"    {str(k):<24} {g.d.median():+.4f}  (n={len(g)})")
PYEOF
else
  echo "(armI eval_val_per_station.csv absent -- training not finished)"
fi
echo "=== END seq=96 ==="
