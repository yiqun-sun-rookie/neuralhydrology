#!/bin/bash
# TUKF09-455 v2r6: submit exactly one preparation job.
# It installs the private runtime offline, stages the 455-basin training and
# validation sources from the read-only capsule, initializes the result root,
# installs and independently seals the 455 rebound filter units, and publishes
# the preparation probe.  It runs no neural training and no formal evaluation.

set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r6_20260902
JOB="$ROOT/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r6/probe_gpu.slurm"
LOCK="$ROOT/status/preparation_submission.lock"

echo "=== PRECONDITIONS ==="
test -f "$JOB" && echo "JOB_SCRIPT_PRESENT" || { echo "JOB_SCRIPT_MISSING"; exit 1; }
sha256sum "$JOB"
test -d "$ROOT/offline_inputs_v2r6" && echo "OFFLINE_INPUTS_PRESENT" || { echo "OFFLINE_INPUTS_MISSING"; exit 1; }
sha256sum "$ROOT/offline_inputs_v2r6/manifest.json"
test ! -e "$ROOT/runtime_v2r6" && echo "PRIVATE_RUNTIME_ABSENT_AS_EXPECTED" || echo "PRIVATE_RUNTIME_ALREADY_PRESENT"
test ! -e "$ROOT/status/hpc_technical_admission.json" && echo "TECHNICAL_ADMISSION_ABSENT_AS_EXPECTED" || echo "TECHNICAL_ADMISSION_ALREADY_PRESENT"
test ! -e "$ROOT/status/training_job_id.txt" && echo "NO_TRAINING_JOB_YET" || echo "TRAINING_JOB_ALREADY_RECORDED"

echo "=== SINGLE PREPARATION SUBMISSION LOCK ==="
if mkdir "$LOCK" 2>/dev/null; then
  echo "PREPARATION_LOCK_ACQUIRED"
else
  echo "PREPARATION_LOCK_ALREADY_PRESENT_NOT_RESUBMITTING"
  cat "$ROOT/status/preparation_job_id.txt" 2>&1
  exit 0
fi

echo "=== SUBMIT EXACTLY ONE PREPARATION JOB ==="
out=$(sbatch "$JOB" 2>&1)
echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
if [ -z "$JID" ]; then
  echo "SUBMIT_FAILED_NO_JOB_NUMBER_RETURNED"
  rmdir "$LOCK" 2>/dev/null
  exit 1
fi
printf '%s' "$JID" > "$ROOT/status/preparation_job_id.txt"
echo "PREPARATION_JOB_ID=$JID"

echo "=== IMMEDIATE STATE ==="
squeue -j "$JID" -o "%.10i %.26j %.8P %.10T %.24R %.8M" 2>&1
squeue -j "$JID" -h --start -o '%S' 2>&1
sinfo -p hgpu8 -o "%.10P %.6a %.6D %.6t %.30N" 2>&1

echo "TUKF09_455_V2R6_PREPARATION_SUBMITTED_ONCE_NO_TRAINING_NO_FORMAL_EVALUATION"
