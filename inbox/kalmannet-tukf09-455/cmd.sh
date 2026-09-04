#!/bin/bash
# TUKF09-455 v2r9 status. Read-only, submits nothing, changes nothing.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r9_20260904
JID=$(cat "$ROOT/status/preparation_job_id.txt" 2>/dev/null)
TID=$(cat "$ROOT/status/training_job_id.txt" 2>/dev/null)
echo "TIME=$(date -Is)"
echo "PREPARATION_JOB_ID=$JID  TRAINING_JOB_ID=$TID"
sacct -j "$JID" -X --format=JobID%10,State%12,ExitCode%8,NodeList%9,Elapsed%10,Start%20,End%20 2>&1
[ -n "$TID" ] && sacct -j "$TID" -X --format=JobID%10,State%12,ExitCode%8,NodeList%9,Elapsed%10,Start%20,End%20 2>&1
squeue -u "$USER" -h -o "%.10i %.26j %.9T %.16R %.10M" 2>&1 | grep tukf09 || echo NO_TUKF09_JOB_IN_QUEUE
sinfo -p hgpu8 -o "%.10P %.6a %.6D %.8t %.24N %.20C" 2>&1
echo "=== MARKERS ==="
for f in PREPARATION_FAILED.json initial_bundle_verification.json staged_training_sources.json preparation_probe.json hpc_technical_admission.json training_job_id.txt training_verification.json; do
  if [ -f "$ROOT/status/$f" ]; then echo "PRESENT $f  $(sha256sum "$ROOT/status/$f" | cut -d" " -f1)"; else echo "ABSENT  $f"; fi
done
ls "$ROOT/status" 2>&1
if [ -d "$ROOT/runtime_v2r9" ]; then echo "PRIVATE_RUNTIME_PRESENT $(du -sh "$ROOT/runtime_v2r9" | cut -f1)"; else echo PRIVATE_RUNTIME_ABSENT; fi
RR="$ROOT/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
if [ -d "$RR" ]; then
  echo "FILTER_UNITS=$(ls "$RR/filter" 2>/dev/null | wc -l)"
  echo "NEURAL_UNITS=$(ls "$RR/neural" 2>/dev/null | wc -l)"
  echo "NEURAL_CHECKPOINTS=$(find "$RR/neural" -type f -name "*.pt" 2>/dev/null | wc -l)"
  ls "$RR/neural" 2>/dev/null | head -12
  echo "SELECTION=$(test -e "$RR/selection" && echo PRESENT || echo ABSENT)"
  echo "EVALUATION=$(test -e "$RR/evaluation" && echo PRESENT || echo ABSENT)"
else
  echo RESULT_ROOT_ABSENT
fi
echo "=== LOG TAILS ==="
tail -c 2200 "$ROOT/logs/prepare-$JID.out" 2>&1
tail -c 900 "$ROOT/logs/prepare-$JID.err" 2>&1
[ -n "$TID" ] && { tail -c 2200 "$ROOT/logs/training-$TID.out" 2>&1; tail -c 900 "$ROOT/logs/training-$TID.err" 2>&1; }
echo "=== FROZEN EVIDENCE UNCHANGED ==="
sha256sum /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901/logs/training-217939.out 2>&1
echo "CAPSULE_V2_MODE=$(stat -c %a /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v2_20260901)"
echo "CAPSULE_V3_MODE=$(stat -c %a /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v3_20260904)"
echo TUKF09_455_V2R9_STATUS_READ_ONLY
