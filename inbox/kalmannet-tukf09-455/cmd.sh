#!/bin/bash
# TUKF09-455 v2r8: submit exactly one preparation job once the runtime inputs are
# published. No training job, no formal evaluation.

set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r8_20260904
JOB="$ROOT/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r8/probe_gpu.slurm"
LOCK="$ROOT/status/preparation_submission.lock"

echo "TIME=$(date -Is)"
echo "=== DOWNLOAD STATE ==="
pgrep -f download_runtime_inputs_login.sh >/dev/null 2>&1 && echo DOWNLOADER_RUNNING || echo DOWNLOADER_NOT_RUNNING
if [ -d "$ROOT/offline_inputs_v2r8" ]; then
  echo OFFLINE_INPUTS_PUBLISHED
  du -sh "$ROOT/offline_inputs_v2r8"
  sha256sum "$ROOT/offline_inputs_v2r8/manifest.json"
  echo "OFFLINE_FILES=$(find "$ROOT/offline_inputs_v2r8" -type f | wc -l)"
else
  echo OFFLINE_INPUTS_NOT_READY
  du -sh "$ROOT"/offline_inputs_v2r8.pending.* 2>&1
  tail -c 500 "$ROOT/logs/offline-inputs-download.log" 2>&1
  echo TUKF09_455_V2R8_WAITING_FOR_OFFLINE_INPUTS_NO_JOB_SUBMITTED
  exit 0
fi

echo "=== SUBMISSION PRECONDITIONS ==="
test -f "$JOB" || { echo JOB_SCRIPT_MISSING; exit 1; }
grep -c "SBATCH --exclusive" "$JOB"
grep -c "SBATCH --exclude" "$JOB"
test ! -e "$ROOT/runtime_v2r8" && echo PRIVATE_RUNTIME_ABSENT_AS_EXPECTED || echo PRIVATE_RUNTIME_ALREADY_PRESENT
test ! -e "$ROOT/status/hpc_technical_admission.json" && echo NO_TECHNICAL_ADMISSION_YET || echo TECHNICAL_ADMISSION_ALREADY_PRESENT
test ! -e "$ROOT/status/training_job_id.txt" && echo NO_TRAINING_JOB_YET || echo TRAINING_JOB_ALREADY_RECORDED
test ! -e "$ROOT/status/PREPARATION_FAILED.json" && echo NO_PREPARATION_FAILURE_MARKER || { echo ROOT_ALREADY_FROZEN; exit 1; }

echo "=== SINGLE PREPARATION SUBMISSION LOCK ==="
if mkdir "$LOCK" 2>/dev/null; then
  echo PREPARATION_LOCK_ACQUIRED
else
  echo PREPARATION_LOCK_ALREADY_PRESENT_NOT_RESUBMITTING
  cat "$ROOT/status/preparation_job_id.txt" 2>&1
  exit 0
fi

echo "=== SUBMIT EXACTLY ONE PREPARATION JOB ==="
out=$(sbatch "$JOB" 2>&1)
echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
if [ -z "$JID" ]; then echo SUBMIT_FAILED; rmdir "$LOCK" 2>/dev/null; exit 1; fi
printf "%s" "$JID" > "$ROOT/status/preparation_job_id.txt"
echo "PREPARATION_JOB_ID=$JID"

echo "=== IMMEDIATE STATE ==="
squeue -j "$JID" -o "%.10i %.26j %.8P %.10T %.24R %.8M" 2>&1
sinfo -p hgpu8 -o "%.10P %.6a %.6D %.8t %.24N %.20C" 2>&1
echo TUKF09_455_V2R8_PREPARATION_SUBMITTED_ONCE_NO_TRAINING_NO_FORMAL_EVALUATION
