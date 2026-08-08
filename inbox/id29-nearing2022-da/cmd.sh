#!/bin/bash
# ID29 seq=13: light progress check. Read-only, no waiting, no ssh, no wildcard deletes.
ROOT=/data1/home/sunyiq/nearing2022_da
RES=$ROOT/results/29_nearing2022_da_ar

echo "=== queue ==="
squeue -u "$USER" -o "%.10i %.12j %.11T %.12M %.12l %.16R" 2>&1

for tag in simulation_seed0 autoregression; do
  D=$(ls -1dt $RES/nearing2022_${tag}_*/ 2>/dev/null | head -1)
  echo "=== $tag ==="
  if [ -n "$D" ] && [ -f "$D/output.log" ]; then
    echo "  epochs done: $(grep -cE 'Epoch [0-9]+ average loss' "$D/output.log") / 30"
    grep -E "Epoch [0-9]+ average loss" "$D/output.log" | tail -2 | sed 's/^/    /'
    grep -E "Median validation metrics" "$D/output.log" | tail -1 | cut -c1-200 | sed 's/^/    /'
  else
    echo "  no output.log yet ($D)"
  fi
done

echo "=== has the simulation started its test evaluation / finished ==="
S=$(ls -1dt $RES/nearing2022_simulation_seed0_*/ 2>/dev/null | head -1)
ls "$S/test" 2>/dev/null && find "$S/test" -name "test_metrics.csv" 2>/dev/null | head -2
sacct -j 201858,201890,201893 -X --format=JobID%10,JobName%12,State%12,Elapsed%10,Timelimit%12 2>&1 | head -6
