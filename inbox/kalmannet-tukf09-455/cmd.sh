#!/bin/bash
# TUKF09-455 v2r7: retire the queued v2r6 preparation job and deploy the bundle whose
# only change is dropping the inherited node exclusion, after job 219417 health-checked
# that node. Submits no preparation and no training job here.

set -o pipefail

R7=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r7_20260904
R6=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r6_20260902
R5=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
PAY="$PWD/payload/kalmannet-tukf09-455/a800-exclusive-v2r7-node-exclusion"
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

echo "=== SCOPE GUARD ==="
echo "NEW_ROOT=$R7"
case "$R7" in
  *v2r4*|*v2r5*|*v2r6*|*training_source_capsule*) echo "SCOPE_GUARD_FAILED"; exit 1;;
esac
echo "SCOPE_GUARD_OK"

echo "=== RETIRE THE QUEUED v2r6 PREPARATION JOB ==="
OLD=$(cat "$R6/status/preparation_job_id.txt" 2>/dev/null)
echo "OLD_PREPARATION_JOB_ID=$OLD"
sacct -j "$OLD" -X --format=JobID%10,State%12,ExitCode%8,NodeList%9,Elapsed%10 2>&1
STATE=$(squeue -j "$OLD" -h -o "%T" 2>/dev/null)
echo "CURRENT_STATE=$STATE"
if [ "$STATE" = "PENDING" ]; then
  scancel "$OLD" 2>&1
  echo "SCANCEL_ISSUED"
  sleep 5
  sacct -j "$OLD" -X --format=JobID%10,State%12,ExitCode%8 2>&1
elif [ -z "$STATE" ]; then
  echo "ALREADY_GONE_FROM_QUEUE_NOT_CANCELLING"
else
  echo "NOT_PENDING_STATE=$STATE_REFUSING_TO_CANCEL"
  exit 1
fi
echo "--- the superseded root itself is left untouched ---"
ls -ld "$R6" 2>&1
test -e "$R6/status/hpc_technical_admission.json" && echo "V2R6_ADMISSION_PRESENT_UNEXPECTED" || echo "V2R6_NEVER_ADMITTED_AS_EXPECTED"
test -e "$R6/status/training_job_id.txt" && echo "V2R6_TRAINING_SUBMITTED_UNEXPECTED" || echo "V2R6_NO_TRAINING_EVER_SUBMITTED"

echo "=== FROZEN v2r5 EVIDENCE UNCHANGED ==="
echo "V2R5_JOB_ID_FILE=$(cat "$R5/status/training_job_id.txt" 2>&1)"
sha256sum "$R5/logs/training-217939.out" "$R5/logs/training-217939.err" 2>&1

echo "=== PAYLOAD EXACT GATE ==="
A=$(sha256sum "$PAY/tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r7_formal_training.tar.gz" | cut -d' ' -f1)
B=$(sha256sum "$PAY/bundle_manifest.sha256.json" | cut -d' ' -f1)
C=$(sha256sum "$PAY/build_tukf09_455_a800_exclusive_hpc_bundle_v2r7.py" | cut -d' ' -f1)
S=$(wc -c < "$PAY/tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r7_formal_training.tar.gz")
echo "ARCHIVE_SHA256=$A"; echo "ARCHIVE_SIZE=$S"; echo "MANIFEST_SHA256=$B"; echo "BUILDER_SHA256=$C"
test "$A" = "8a8cbcf31e272d0e48debfbe507a35dea8175ce9059c353dbc213cf358a4c03f" || { echo "ARCHIVE_HASH_MISMATCH"; exit 1; }
test "$S" = "9914038" || { echo "ARCHIVE_SIZE_MISMATCH"; exit 1; }
test "$B" = "656f20bc4071c7e48d65dde88b4f142d9ee2d2f68466ea180287c732b10ff4fb" || { echo "MANIFEST_HASH_MISMATCH"; exit 1; }
test "$C" = "0ece076b1393068f00de3035fd8a9013915a011ac1b70796fc5c842dbd6c2d2c" || { echo "BUILDER_HASH_MISMATCH"; exit 1; }
echo "PAYLOAD_EXACT_GATE_PASS"

echo "=== EXCLUSIVE NEW ROOT RESERVATION ==="
if mkdir "$R7" 2>/dev/null; then echo "NEW_ROOT_RESERVED"; else echo "NEW_ROOT_ALREADY_EXISTS"; ls -ld "$R7"; exit 1; fi
mkdir -p "$R7/logs" "$R7/status"

echo "=== EXTRACT ==="
"$PY" -B "$PAY/build_tukf09_455_a800_exclusive_hpc_bundle_v2r7.py" --archive "$PAY/tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r7_formal_training.tar.gz" --extract-to "$R7/bundle" 2>&1
echo "=== STRICT EXTRACTED VERIFICATION ==="
"$PY" -B "$PAY/build_tukf09_455_a800_exclusive_hpc_bundle_v2r7.py" --verify-extracted "$R7/bundle" 2>&1

echo "=== NODE EXCLUSION IS GONE, EXCLUSIVITY IS NOT ==="
grep -n "SBATCH --exclusive\|SBATCH --exclude\|SBATCH --nodelist" "$R7/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r7/probe_gpu.slurm" "$R7/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r7/submit_training_gpu.slurm" 2>&1
sha256sum "$R7/bundle/kalmannet/scripts/run_tukf09_455_neural_training_controller.py" 2>&1
sha256sum "$R7/bundle/kalmannet/artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/training_admission/training_admission.json" 2>&1
test -e "$R7/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1" && echo "RESULTS_PRESENT_UNEXPECTED" || echo "RESULTS_ABSENT_AS_REQUIRED"

echo "=== PARTITION NOW ==="
sinfo -p hgpu8 -o "%.10P %.6a %.6D %.8t %.24N %.20C" 2>&1

echo "TUKF09_455_A800_EXCLUSIVE_V2R7_DEPLOYED_OLD_JOB_RETIRED_NO_JOB_SUBMITTED"
