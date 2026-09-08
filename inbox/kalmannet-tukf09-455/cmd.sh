#!/bin/bash
# TUKF09-455 v2r12: submit the single preparation job. One submission, guarded by a lock.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r12_20260908
P="$ROOT/bundle/kalmannet"
S="$P/hpc/tukf09_455_basin_revision_a800_exclusive_v2r12/probe_gpu.slurm"
echo "TIME=$(date -Is)"
echo "=== PRECONDITIONS ==="
test -f "$S" || { echo SLURM_FILE_MISSING; exit 10; }
test -f "$ROOT/offline_inputs_v2r12/manifest.json" || { echo OFFLINE_INPUTS_MISSING; exit 11; }
echo "OFFLINE_MANIFEST_SHA256=$(sha256sum "$ROOT/offline_inputs_v2r12/manifest.json"|cut -d" " -f1)"
echo "EXCLUSIVE_DIRECTIVES=$(grep -c -- "--exclusive" "$S" || true)"
grep -E "^#SBATCH (-p|-N|-n|--cpus-per-task|--gres|-t)" "$S"
if [ -d "$ROOT/status/preparation_submission.lock" ]; then echo PREPARATION_ALREADY_SUBMITTED; cat "$ROOT/status/preparation_job_id.txt" 2>/dev/null; exit 0; fi
mkdir "$ROOT/status/preparation_submission.lock" || { echo LOCK_RACE; exit 12; }
echo "=== SUBMIT ==="
JID=$(sbatch --parsable "$S")
JID=${JID%%;*}
echo "$JID" > "$ROOT/status/preparation_job_id.txt"
echo "PREPARATION_JOB_ID=$JID"
sleep 20
squeue -j "$JID" -o "%.10i %.10T %.11M %.11l %.9N %.24R" 2>&1
sacct -j "$JID" -X --format=JobID%10,State%12,Elapsed%10,NodeList%9 2>&1
echo "=== NO TRAINING JOB YET ==="
test -f "$ROOT/status/training_job_id.txt" && cat "$ROOT/status/training_job_id.txt" || echo TRAINING_NOT_SUBMITTED
echo TUKF09_455_V2R12_PREPARATION_SUBMITTED
