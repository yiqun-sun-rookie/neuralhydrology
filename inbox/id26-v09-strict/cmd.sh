#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/v09_strict
PREDICT_REPO=$ROOT/predict_v09/neuralhydrology
mkdir -p $ROOT/logs

echo "=== A SUBMIT ==="
cd $PREDICT_REPO || exit 1
out=$(sbatch src/26_historical_band_experts/hpc/predict_formal_v09.slurm 2>&1)
echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
if [ -z "$JID" ]; then echo "SUBMIT_FAILED"; exit 1; fi
echo "$JID" > $ROOT/predict_v09/predict_attempt_01_jobid.txt
echo "jobid=$JID"

echo "=== B QUEUE STATE ==="
sacct -j "$JID" -X --format=JobID%10,JobName%12,State%12,Elapsed%10 2>&1 | head -5
echo "est_start=$(squeue -j $JID -h --start -o '%S' 2>/dev/null || true)"
echo "reason=$(squeue -j $JID -h -o '%r' 2>/dev/null || true)"
echo "=== END ==="
