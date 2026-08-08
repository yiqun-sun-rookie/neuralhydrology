#!/bin/bash
# ID29 seq=14: wait for the simulation arm to finish (bounded at 40 min) and report its final metrics.
# One bounded wait instead of many short polls. Nothing heavy runs here - it is a squeue poll.
ROOT=/data1/home/sunyiq/nearing2022_da
RES=$ROOT/results/29_nearing2022_da_ar

echo "=== wait for 201858 (max 40 min) ==="
for i in $(seq 1 120); do
    ST=$(squeue -j 201858 -h -o "%t" 2>/dev/null)
    [ -z "$ST" ] && { echo "  simulation left the queue after $((i*20))s"; break; }
    [ $((i % 15)) -eq 0 ] && echo "  t=$((i*20))s state=$ST epochs=$(grep -cE 'Epoch [0-9]+ average loss' $RES/nearing2022_simulation_seed0_*/output.log 2>/dev/null)"
    sleep 20
done

echo "=== job outcome ==="
sacct -j 201858,201890,201893 -X --format=JobID%10,JobName%12,State%12,ExitCode%8,Elapsed%10 2>&1 | head -6

S=$(ls -1dt $RES/nearing2022_simulation_seed0_*/ 2>/dev/null | head -1)
S=${S%/}
echo "=== simulation run: $S ==="
echo "  epochs done: $(grep -cE 'Epoch [0-9]+ average loss' "$S/output.log" 2>/dev/null) / 30"

echo "=== SIMULATION TEST METRICS (median over basins) ==="
M=$(find "$S/test" -name "test_metrics.csv" 2>/dev/null | head -1)
if [ -n "$M" ]; then
  echo "  file: $M"
  /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<PYEOF
import pandas as pd
df = pd.read_csv("$M", index_col=0)
paper = {'NSE':0.796,'KGE':0.795,'Alpha-NSE':0.874,'Pearson-r':0.902,'Beta-NSE':-0.027,'Peak-Timing':0.263,'Missed-Peaks':0.352}
print(f"  basins scored: {len(df)}")
print(f"  {'metric':14s} {'ours':>8s} {'paper':>8s} {'diff':>8s}")
for k, v in paper.items():
    if k in df.columns:
        m = df[k].median()
        print(f"  {k:14s} {m:8.3f} {v:8.3f} {m-v:+8.3f}")
PYEOF
else
  echo "  no test_metrics.csv yet (evaluation may still be running)"
fi

echo "=== did the assimilation job start ==="
squeue -u "$USER" -o "%.10i %.12j %.11T %.12M %.16R" 2>&1

echo "=== autoregression progress ==="
A=$(ls -1dt $RES/nearing2022_autoregression_*/ 2>/dev/null | head -1)
echo "  epochs done: $(grep -cE 'Epoch [0-9]+ average loss' "$A/output.log" 2>/dev/null) / 30"
