#!/bin/bash
# ID29 seq=7: measure the real per-epoch rate at 531 basins so the ETA stops being an extrapolation.
ROOT=/data1/home/sunyiq/nearing2022_da

echo "=== A: wait 5 min so at least one epoch boundary is visible ==="
sleep 300

echo "=== B: queue ==="
squeue -u "$USER" -o "%.10i %.10P %.12j %.8T %.12M %.12l %R" 2>&1

echo "=== C: simulation (201858) progress ==="
grep -hE "Epoch [0-9]+ average loss|Median validation" "$ROOT/logs/sim_201858.out" "$ROOT/logs/sim_201858.err" 2>/dev/null | tail -5
echo "-- last progress line --"
tr '\r' '\n' < "$ROOT/logs/sim_201858.err" 2>/dev/null | tail -1 | cut -c1-160

echo "=== D: autoregression (201859) progress ==="
grep -hE "Epoch [0-9]+ average loss|Median validation" "$ROOT/logs/ar_201859.out" "$ROOT/logs/ar_201859.err" 2>/dev/null | tail -5
echo "-- last progress line --"
tr '\r' '\n' < "$ROOT/logs/ar_201859.err" 2>/dev/null | tail -1 | cut -c1-160

echo "=== E: any errors ==="
for f in "$ROOT/logs/sim_201858.err" "$ROOT/logs/ar_201859.err"; do
  echo "-- $(basename $f)"
  grep -iE "error|traceback|CUDA out of memory|Killed" "$f" 2>/dev/null | head -4
done

echo "=== F: gpu utilisation on the shared node ==="
ssh -o BatchMode=yes -o ConnectTimeout=10 ngu104 "nvidia-smi --query-gpu=index,name,memory.used,utilization.gpu --format=csv,noheader" 2>&1 | head -6
