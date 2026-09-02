#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/v09_strict
JID=$(cat $ROOT/predict_v09/predict_attempt_01_jobid.txt 2>/dev/null || echo "")

echo "=== A BEFORE ==="
squeue -j "$JID" -h -o "%i %P %T %r %S" 2>&1 || true

echo "=== B MOVE TO hgpu2 (same RTX 3090 model, two idle nodes) ==="
scontrol update jobid="$JID" partition=hgpu2 2>&1 && echo "update_rc=ok" || echo "update_rc=FAILED"

echo "=== C AFTER ==="
sleep 8
squeue -j "$JID" -h -o "%i %P %T %r %S %N" 2>&1 || true
sacct -j "$JID" -X -P --format=JobID,State,Partition,NodeList,Elapsed 2>&1 | head -3

echo "=== D ONLY MY JOB TOUCHED ==="
squeue -u "$USER" -h -o "%.10i %.12j %.9P %.9T" 2>&1 | head -12
echo "=== END ==="
