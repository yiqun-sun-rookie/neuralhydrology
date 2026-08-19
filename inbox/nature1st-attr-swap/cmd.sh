#!/bin/bash
# nature1st-attr-swap seq=11 -- STATUS, and the PAIRED ANALYSIS once both arms finish.
# NO sbatch anywhere: 206175 (control) / 206176 (treatment) are the only runs and the
# treatment already COMPLETED (early stop at epoch 13, best 0.5983 at epoch 8).
# The paired stats are computed here because the per-station CSVs live on this side.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
CTRL=206175
TREAT=206176

echo "=== A. JOB STATE ==="
sacct -j $CTRL,$TREAT -X --format=JobID%10,JobName%22,State%14,ExitCode%8,Elapsed%12,NodeList%9 2>&1

echo "=== B. CONTROL PROGRESS (tail) ==="
f=$(ls "$RUN"/logs/attr_swap/*-${CTRL}.out 2>/dev/null | head -1)
[ -n "$f" ] && grep -E 'val_median_NSE|Best median NSE|Done\.' "$f" 2>/dev/null | tail -8

echo "=== C. EVAL ARTIFACTS ==="
for d in q_lstm_control_hpc_s42 q_lstm_hydroatlas_hpc_s42; do
    echo "--- $d ---"
    ls -la "$RUN/models/$d"/eval_val.json "$RUN/models/$d"/eval_val_per_station.csv 2>&1 | head -3
done

echo "=== D. PAIRED ANALYSIS (only when both per-station files exist) ==="
A="$RUN/models/q_lstm_control_hpc_s42/eval_val_per_station.csv"
B="$RUN/models/q_lstm_hydroatlas_hpc_s42/eval_val_per_station.csv"
if [ -f "$A" ] && [ -f "$B" ]; then
    source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
    conda activate nh_final 2>/dev/null
    python - "$A" "$B" <<'PY'
import sys
import numpy as np, pandas as pd
us  = pd.read_csv(sys.argv[1]).set_index("station")
glo = pd.read_csv(sys.argv[2]).set_index("station")
j = glo[["nse","stratum"]].join(us[["nse"]], lsuffix="_glob", rsuffix="_us").dropna(subset=["nse_glob","nse_us"])
d = (j.nse_glob - j.nse_us).values
rng = np.random.default_rng(0)
bs = [np.median(rng.choice(d, len(d), replace=True)) for _ in range(5000)]
print(f"paired stations       {len(j)}")
print(f"control  median NSE   {j.nse_us.median():.4f}   p25 {j.nse_us.quantile(.25):.4f}  p75 {j.nse_us.quantile(.75):.4f}")
print(f"global   median NSE   {j.nse_glob.median():.4f}   p25 {j.nse_glob.quantile(.25):.4f}  p75 {j.nse_glob.quantile(.75):.4f}")
print(f"group median diff     {j.nse_glob.median()-j.nse_us.median():+.4f}   <-- the pre-registered statistic")
print(f"PAIRED median diff    {np.median(d):+.4f}   95%CI [{np.percentile(bs,2.5):+.4f}, {np.percentile(bs,97.5):+.4f}]")
print(f"worse / better        {(d<0).sum()} / {(d>0).sum()}  ({(d<0).mean()*100:.1f}% worse)")
print(f"|change|<0.05         {(np.abs(d)<0.05).mean()*100:.1f}%   lost>0.10 {(d<-0.10).mean()*100:.1f}%   gained>0.10 {(d>0.10).mean()*100:.1f}%")
print(f"crossed zero          us>0&glob<0: {int(((j.nse_us>0)&(j.nse_glob<0)).sum())}   reverse: {int(((j.nse_us<0)&(j.nse_glob>0)).sum())}")
try:
    from scipy.stats import wilcoxon
    print(f"wilcoxon p            {wilcoxon(j.nse_glob, j.nse_us)[1]:.3e}")
except Exception as e:
    print("wilcoxon unavailable:", e)
for lab, m in [("usable (ctrl>0)", j.nse_us > 0), ("good (ctrl>0.5)", j.nse_us > 0.5)]:
    g = j[m]; dd = (g.nse_glob - g.nse_us).values
    print(f"{lab:<18} n={len(g):>3}  group diff {g.nse_glob.median()-g.nse_us.median():+.4f}  paired {np.median(dd):+.4f}")
print("-- by stratum (paired) --")
for s, g in j.groupby("stratum"):
    print(f"  {s:<12} n={len(g):>3}  ctrl {g.nse_us.median():.4f}  glob {g.nse_glob.median():.4f}  paired {np.median((g.nse_glob-g.nse_us).values):+.4f}")
PY
else
    echo "(control eval not written yet -- rerun this poll after 206175 finishes)"
fi
echo "=== END seq=11 ==="
