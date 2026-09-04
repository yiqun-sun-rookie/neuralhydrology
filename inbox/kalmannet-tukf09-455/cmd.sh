#!/bin/bash
# TUKF09-455: release the exclusive node. The running job can only finish one of the
# nine models before its wall clock expires, and it holds eight cards to use one, so
# it is retired rather than left occupying a shared node. Its root is left in place as
# evidence. Nothing else is submitted, retried or modified.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r10_20260904
TID=$(cat "$ROOT/status/training_job_id.txt" 2>/dev/null)
RR="$ROOT/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
echo "TIME=$(date -Is)  TRAINING_JOB_ID=$TID"

echo "=== STATE BEFORE ==="
sacct -j "$TID" -X --format=JobID%10,State%10,Elapsed%10,NodeList%9 2>&1
echo "CHECKPOINTS=$(find "$RR/neural" -type f -name "*.pt" 2>/dev/null | wc -l)"
echo "COMPLETE_UNITS=$(find "$RR/neural" -maxdepth 1 -type d -name "lead_*_seed_*" -not -name "*.pending-*" 2>/dev/null | wc -l)"

echo "=== RETIRE ==="
STATE=$(squeue -j "$TID" -h -o "%T" 2>/dev/null)
echo "CURRENT_STATE=$STATE"
if [ "$STATE" = "RUNNING" ] || [ "$STATE" = "PENDING" ]; then
  scancel "$TID" 2>&1
  echo SCANCEL_ISSUED
  sleep 12
elif [ -z "$STATE" ]; then
  echo ALREADY_GONE_FROM_QUEUE
else
  echo "UNEXPECTED_STATE=$STATE"; exit 1
fi
sacct -j "$TID" -X --format=JobID%10,State%14,ExitCode%8,Elapsed%10 2>&1

echo "=== NODE RELEASED ==="
sinfo -p hgpu8 -o "%.10P %.6a %.6D %.8t %.24N %.20C" 2>&1

echo "=== PARTIAL WORK LEFT IN PLACE AS EVIDENCE ==="
echo "CHECKPOINTS=$(find "$RR/neural" -type f -name "*.pt" 2>/dev/null | wc -l)"
ls -la "$RR/neural" 2>&1
echo "SELECTION=$(test -e "$RR/selection" && echo PRESENT || echo ABSENT) EVALUATION=$(test -e "$RR/evaluation" && echo PRESENT || echo ABSENT)"

echo "=== FROZEN EVIDENCE UNCHANGED ==="
sha256sum /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901/logs/training-217939.out 2>&1
for c in v2 v3 v4 v5; do echo "CAPSULE_${c}_MODE=$(stat -c %a /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_${c}_2026090* 2>/dev/null | head -1)"; done

echo TUKF09_455_V2R10_TRAINING_RETIRED_NODE_RELEASED_NOTHING_RESUBMITTED
