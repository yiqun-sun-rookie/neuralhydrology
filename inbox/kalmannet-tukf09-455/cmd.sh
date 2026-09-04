#!/bin/bash
# TUKF09-455 v2r9: submit exactly one neural training job. Nine models, three seeds
# per lead, thirty epochs each, one GPU, serial. No formal evaluation.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r9_20260904
PROJECT="$ROOT/bundle/kalmannet"
JOB="$PROJECT/hpc/tukf09_455_basin_revision_a800_exclusive_v2r9/submit_training_gpu.slurm"
ADM="$ROOT/status/hpc_technical_admission.json"
LOCK="$ROOT/status/training_submission.lock"

echo "TIME=$(date -Is)"
echo "=== PRECONDITIONS ==="
test -f "$JOB" || { echo JOB_SCRIPT_MISSING; exit 1; }
test -f "$ADM" || { echo TECHNICAL_ADMISSION_MISSING; exit 1; }
test ! -e "$ROOT/status/PREPARATION_FAILED.json" || { echo ROOT_FROZEN; exit 1; }
echo "ADMISSION_SHA256=$(sha256sum "$ADM" | cut -d" " -f1)"
grep -o '"status": "[A-Z_0-9]*"' "$ADM" | tail -1
grep -o '"formal_evaluation_authorized": [a-z]*' "$ADM" | tail -1
grep -o '"ordered_basin_count": [0-9]*' "$ADM" | tail -1
grep -o '"scientific_contract_changed": [a-z]*' "$ADM" | tail -1
echo "EXCLUSIVE_DIRECTIVES=$(grep -c "SBATCH --exclusive" "$JOB")  EXCLUDE_DIRECTIVES=$(grep -c "SBATCH --exclude" "$JOB")"
RR="$PROJECT/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
echo "FILTER_UNITS=$(ls "$RR/filter" 2>/dev/null | wc -l) NEURAL_UNITS=$(ls "$RR/neural" 2>/dev/null | wc -l)"

echo "=== SINGLE TRAINING SUBMISSION LOCK ==="
if mkdir "$LOCK" 2>/dev/null; then
  echo TRAINING_LOCK_ACQUIRED
else
  echo TRAINING_LOCK_ALREADY_PRESENT_NOT_RESUBMITTING
  cat "$ROOT/status/training_job_id.txt" 2>&1
  exit 0
fi

echo "=== SUBMIT EXACTLY ONE TRAINING JOB ==="
out=$(sbatch "$JOB" 2>&1)
echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
if [ -z "$JID" ]; then echo SUBMIT_FAILED; rmdir "$LOCK" 2>/dev/null; exit 1; fi
printf "%s" "$JID" > "$ROOT/status/training_job_id.txt"
chmod 0444 "$ROOT/status/training_job_id.txt"
echo "TRAINING_JOB_ID=$JID"

echo "=== IMMEDIATE STATE ==="
squeue -j "$JID" -o "%.10i %.26j %.8P %.10T %.24R %.8M %.12l" 2>&1
sinfo -p hgpu8 -o "%.10P %.6a %.6D %.8t %.24N %.20C" 2>&1
echo TUKF09_455_V2R9_NEURAL_TRAINING_SUBMITTED_ONCE_FORMAL_EVALUATION_HOLD
