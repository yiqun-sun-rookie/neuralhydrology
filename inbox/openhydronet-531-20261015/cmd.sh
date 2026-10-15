#!/bin/bash
set -o pipefail
# read-only: epoch summary lines of the native531 job
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
date --iso-8601=seconds
squeue -u sunyiq -h -o '%.10i %.14j %.9T %.10M %R' | grep -E ' ohn_' || echo "no ohn job in queue"
F=$(ls -t "$ROOT"/logs/ohn_native531-*.out | head -1)
echo "log=$F"
grep -aE "Epoch [0-9]+ average" "$F" | sed -E 's/^\[INFO\] //' | cut -c1-330 | tail -8
echo "--- current progress"
tr '\r' '\n' < "$F" | grep -aE "^# (Epoch|Validation)" | tail -1 | cut -c1-160
grep -aE "Traceback|Error|OutOfMemory|CUDA out" "$F" "${F%.out}.err" | head -5 | cut -c1-200
exit 0
