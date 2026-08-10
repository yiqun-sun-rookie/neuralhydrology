#!/bin/bash
# ID29 seq=63: bounded health check for training and immediate evaluation arrays.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
LOG_ROOT="$ROOT/closure_20260810/logs"

echo "=== QUEUE ==="
squeue -j 202214,202215,202216,202222,202226,202227,202228 \
  -o '%.18i %.18j %.2t %.10M %.6D %R' || true

echo "=== ACCOUNTING ==="
sacct -j 202214,202215,202216,202222 \
  --format=JobID,JobName,Partition,State,Elapsed,ExitCode -P | head -80

echo "=== EVALUATION LOG INVENTORY ==="
find "$LOG_ROOT" -maxdepth 1 -type f -name 'N22-eval-now_202222_*' \
  -printf '%f %s bytes\n' | sort | head -40

echo "=== COMPLETED OR FAILED EVALUATION TASK TAILS ==="
for task in 0 1 2 3; do
  out="$LOG_ROOT/N22-eval-now_202222_${task}.out"
  err="$LOG_ROOT/N22-eval-now_202222_${task}.err"
  if [ -f "$out" ]; then
    echo "--- task=$task stdout ---"
    tail -20 "$out"
  fi
  if [ -s "$err" ]; then
    echo "--- task=$task stderr ---"
    tail -20 "$err"
  fi
done
