#!/bin/bash
# TUKF09-455 v2r8: read-only forensics for the failed training job. Submits nothing,
# retries nothing, changes nothing.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r8_20260904
PROJECT="$ROOT/bundle/kalmannet"
RR="$PROJECT/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
L="$RR/logs/formal_training_sequence"
TID=$(cat "$ROOT/status/training_job_id.txt" 2>/dev/null)
echo "TIME=$(date -Is)  TRAINING_JOB_ID=$TID"
sacct -j "$TID" -X --format=JobID%10,State%12,ExitCode%8,NodeList%9,Elapsed%10,Start%20,End%20 2>&1

echo "=== SEQUENCE STAGE LOGS ==="
ls -la "$L" 2>&1
for f in "$L"/*.log; do
  echo "----- $f  $(stat -c %s "$f") bytes  $(sha256sum "$f" | cut -d" " -f1)"
  tail -c 3000 "$f" 2>&1
done

echo "=== SEQUENCE EVENTS ==="
tail -c 3000 "$RR/control/formal_training_sequence/events.jsonl" 2>&1

echo "=== NEURAL CONTROL EVENTS ==="
ls -la "$RR/control/neural" 2>&1
tail -c 3000 "$RR/control/neural/events.jsonl" 2>&1

echo "=== NEURAL TREE ==="
ls -la "$RR/neural" 2>&1
echo "NEURAL_UNITS=$(ls "$RR/neural" 2>/dev/null | wc -l)"
echo "NEURAL_CHECKPOINTS=$(find "$RR/neural" -type f -name "*.pt" 2>/dev/null | wc -l)"

echo "=== OUTER TRAINING LOGS ==="
echo "OUT $(stat -c %s "$ROOT/logs/training-$TID.out" 2>/dev/null) bytes"; tail -c 1500 "$ROOT/logs/training-$TID.out" 2>&1
echo "ERR $(stat -c %s "$ROOT/logs/training-$TID.err" 2>/dev/null) bytes"; cat "$ROOT/logs/training-$TID.err" 2>&1

echo "=== FORMAL EVALUATION STILL CLOSED ==="
echo "SELECTION=$(test -e "$RR/selection" && echo PRESENT || echo ABSENT) EVALUATION=$(test -e "$RR/evaluation" && echo PRESENT || echo ABSENT)"
echo TUKF09_455_V2R8_TRAINING_FORENSICS_READ_ONLY
