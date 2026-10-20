#!/bin/bash
set -o pipefail
# read-only: state + epoch progress of every ohn_* job of this channel
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
date --iso-8601=seconds
echo "=== queue ==="
squeue -u sunyiq -h -o '%.10i %.16j %.9T %.10M %R' | grep -E ' ohn_' || echo "none queued/running"
echo "=== sacct since 10-14 ==="
sacct -X -n -P -S 2026-10-20 --format=JobID,JobName,State,ExitCode,Elapsed,NodeList 2>/dev/null | grep -E '\|ohn_' || echo none
for N in ohn_tune_v0 ohn_tune_v1 ohn_tune_v2 ohn_tune_v3; do
  F=$(ls -t "$ROOT"/logs/$N-*.out 2>/dev/null | head -1)
  [ -n "$F" ] || continue
  echo "=== $N : $(basename "$F")"
  grep -aE "Epoch [0-9]+ average" "$F" | sed -E 's/^\[INFO\] //; s/\(basetrainer.py:train_and_validate\) -- //' | cut -c1-300 | tail -3
  echo "  progress: $(tr '\r' '\n' < "$F" | grep -aE '^# (Epoch|Validation)' | tail -1 | cut -c1-110)"
  grep -aE "Traceback|Error|OutOfMemory|CUDA out|Killed" "$F" "${F%.out}.err" 2>/dev/null | head -3 | cut -c1-200
done
exit 0
