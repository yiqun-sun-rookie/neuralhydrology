#!/bin/bash
# ID29 seq=15: simulation arm finished - read its metrics. Short, read-only, no waiting.
ROOT=/data1/home/sunyiq/nearing2022_da
RES=$ROOT/results/29_nearing2022_da_ar

echo "=== job outcomes ==="
sacct -j 201858,201890,201893 -X --format=JobID%10,JobName%12,State%12,ExitCode%8,Elapsed%10,End%20 2>&1 | head -6

S=$(ls -1dt $RES/nearing2022_simulation_seed0_*/ 2>/dev/null | head -1); S=${S%/}
echo "=== simulation run: $(basename $S) ==="
echo "  epochs: $(grep -cE 'Epoch [0-9]+ average loss' "$S/output.log" 2>/dev/null) / 30"
grep -E "Epoch 30 average loss" "$S/output.log" 2>/dev/null | sed 's/^/  /'

M=$(find "$S/test" -name "test_metrics.csv" 2>/dev/null | head -1)
echo "=== SIMULATION vs PAPER (median over basins) ==="
if [ -n "$M" ]; then
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<PYEOF
import pandas as pd
df = pd.read_csv("$M", index_col=0)
paper = [('NSE',0.796),('KGE',0.795),('Alpha-NSE',0.874),('Pearson-r',0.902),
         ('Beta-NSE',-0.027),('Peak-Timing',0.263),('Missed-Peaks',0.352)]
print(f"  basins scored: {len(df)}")
print(f"  {'metric':14s} {'ours':>8s} {'paper':>8s} {'diff':>8s}")
for k, v in paper:
    if k in df.columns:
        m = df[k].median()
        print(f"  {k:14s} {m:8.3f} {v:8.3f} {m-v:+8.3f}")
PYEOF
else
  echo "  no test_metrics.csv found under $S/test"
  ls -R "$S/test" 2>/dev/null | head -10
fi

echo "=== assimilation progress ==="
D=$(ls -1dt $RES/assimilation_lead_1_holdout_0.0_from_*/ 2>/dev/null | head -1); D=${D%/}
echo "  run: $(basename $D 2>/dev/null)"
tr '\r' '\n' < "$ROOT/logs/da_201890.out" 2>/dev/null | grep -oE "Evaluation: *[0-9]+%\|[^|]*\| *[0-9]+/[0-9]+ \[[^]]*\]" | tail -1 | sed 's/^/  /'

echo "=== autoregression progress ==="
A=$(ls -1dt $RES/nearing2022_autoregression_*/ 2>/dev/null | head -1); A=${A%/}
echo "  epochs: $(grep -cE 'Epoch [0-9]+ average loss' "$A/output.log" 2>/dev/null) / 30"
