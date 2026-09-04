#!/bin/bash
# TUKF09-455 v2r10 training pace. Read-only, submits nothing, changes nothing.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r10_20260904
RR="$ROOT/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
TID=$(cat "$ROOT/status/training_job_id.txt" 2>/dev/null)
echo "TIME=$(date -Is)  TRAINING_JOB_ID=$TID"
sacct -j "$TID" -X --format=JobID%10,State%10,Elapsed%10,Timelimit%10,Start%20 2>&1

echo "=== CHECKPOINT TIMESTAMPS ==="
find "$RR/neural" -type f -name "*.pt" -printf "%T@ %TY-%Tm-%Td %TH:%TM:%TS %s %p\n" 2>/dev/null | sort -n | awk '{printf "%s %s %12d %s\n", $2, $3, $4, $5}'
echo "CHECKPOINTS=$(find "$RR/neural" -type f -name "*.pt" 2>/dev/null | wc -l)"
echo "COMPLETE_UNITS=$(find "$RR/neural" -maxdepth 1 -type d -name "lead_*_seed_*" -not -name "*.pending-*" 2>/dev/null | wc -l)"
ls -la "$RR/neural" 2>&1

echo "=== CURRENT UNIT CONTENTS ==="
for d in "$RR/neural"/lead_*; do echo "--- $d"; ls -la "$d" 2>&1 | head -40; done

echo "=== SHARED SCALER ==="
ls -la "$RR/neural/shared" 2>&1

echo "=== NEURAL EVENT LOG TAIL ==="
tail -c 3000 "$RR/control/neural/events.jsonl" 2>&1

echo "=== GPU USE ON THE ALLOCATED NODE ==="
sstat -j "$TID" --format=JobID,AveCPU,MaxRSS,MaxVMSize 2>&1 | head -5

echo "=== TRAINING LOG TAIL ==="
tail -c 1500 "$ROOT/logs/training-$TID.out" 2>&1
tail -c 800 "$ROOT/logs/training-$TID.err" 2>&1
echo TUKF09_455_V2R10_PACE_READ_ONLY
