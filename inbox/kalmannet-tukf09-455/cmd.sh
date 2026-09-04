#!/bin/bash
# TUKF09-455: report the v2r10 training state, then release the exclusive node.
#
# The reading comes first and is untouched by what follows. The retirement is the
# operator decision already taken: the run holds eight cards to use one, and its wall
# clock cannot reach nine models at the measured pace, so it is retired rather than
# left occupying a shared node. Its root and partial work stay in place as evidence.
# Nothing is resubmitted, no configuration is written, no old root or capsule is touched.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r10_20260904
RR="$ROOT/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
TID=$(cat "$ROOT/status/training_job_id.txt" 2>/dev/null)
echo "TIME=$(date -Is)  TRAINING_JOB_ID=$TID"

echo "=== 1. SLURM STATE ==="
sacct -j "$TID" -X --format=JobID%10,State%12,Elapsed%10,Timelimit%10,Start%20,NodeList%9 2>&1
squeue -j "$TID" -o "%.10i %.10T %.11M %.11l %.9N" 2>&1

echo "=== 2. MODELS AND CHECKPOINTS ==="
echo "COMPLETE_UNITS=$(find "$RR/neural" -maxdepth 1 -type d -name "lead_*_seed_*" -not -name "*.pending-*" 2>/dev/null | wc -l) / 9"
echo "CHECKPOINTS=$(find "$RR/neural" -type f -name "*.pt" 2>/dev/null | wc -l) / 270"
ls -la "$RR/neural" 2>&1
find "$RR/neural" -type f -name "*.pt" -printf "%TY-%Tm-%Td %TH:%TM:%TS %12s %p\n" 2>/dev/null | sort | tail -12

echo "=== 3. STATUS MARKERS ==="
ls -la "$ROOT/status" 2>&1
echo "SELECTION=$(test -e "$RR/selection" && echo PRESENT || echo ABSENT) EVALUATION=$(test -e "$RR/evaluation" && echo PRESENT || echo ABSENT)"

echo "=== 4. INNER CONTROLLER EVENT LOG TAIL ==="
tail -c 2000 "$RR/control/neural/events.jsonl" 2>&1
tail -c 1200 "$ROOT/logs/training-$TID.err" 2>&1

echo "=== 5. RETIRE AND RELEASE THE NODE ==="
STATE=$(squeue -j "$TID" -h -o "%T" 2>/dev/null)
echo "CURRENT_STATE=${STATE:-<not-in-queue>}"
if [ "$STATE" = "RUNNING" ] || [ "$STATE" = "PENDING" ]; then
  scancel "$TID" 2>&1 && echo SCANCEL_ISSUED
  sleep 15
else
  echo ALREADY_OFF_THE_QUEUE_NOTHING_TO_CANCEL
fi
sacct -j "$TID" -X --format=JobID%10,State%14,ExitCode%8,Elapsed%10 2>&1
sinfo -p hgpu8 -o "%.10P %.6a %.6D %.8t %.24N %.20C" 2>&1

echo "=== 6. PARTIAL WORK LEFT IN PLACE ==="
echo "CHECKPOINTS_AFTER=$(find "$RR/neural" -type f -name "*.pt" 2>/dev/null | wc -l)"
echo "COMPLETE_UNITS_AFTER=$(find "$RR/neural" -maxdepth 1 -type d -name "lead_*_seed_*" -not -name "*.pending-*" 2>/dev/null | wc -l)"

echo "=== 7. PRESERVED EVIDENCE UNTOUCHED ==="
for r in v2r4 v2r5 v2r6 v2r7 v2r8 v2r9 v2r10; do d=$(ls -d /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_${r}_2026* 2>/dev/null | head -1); echo "ROOT_${r}=${d:-<absent>}"; done
for c in v2 v3 v4 v5; do d=$(ls -d /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_${c}_2026* 2>/dev/null | head -1); echo "CAPSULE_${c}=${d:-<absent>} mode=$(stat -c %a "$d" 2>/dev/null)"; done

echo "=== 8. FREE SPACE AND PARTITION ==="
df -h /data1/home/sunyiq 2>&1 | tail -2

echo TUKF09_455_V2R10_STATUS_READ_AND_NODE_RELEASED_NOTHING_RESUBMITTED
