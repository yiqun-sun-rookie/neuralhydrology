#!/bin/bash
# TUKF09-455 v2r9: deploy the bundle bound to training source capsule v4 and start
# the runtime input download. The whole-node process gate now treats this run own
# process tree as its own and still hard stops on anything outside it. Nothing
# scientific moves and the whole-node exclusive requirement is unchanged.
# No preparation or training job is submitted here.

set -o pipefail

R8=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r9_20260904
R7=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r8_20260904
R5=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
CAP3=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v4_20260904
CAP2=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v3_20260904
PAY="$PWD/payload/kalmannet-tukf09-455/a800-exclusive-v2r9-process-tree-gate"
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

echo "TIME=$(date -Is)"
echo "=== SCOPE GUARD ==="
case "$R8" in *v2r4*|*v2r5*|*v2r6*|*v2r7*|*v2r8*|*capsule*) echo SCOPE_GUARD_FAILED; exit 1;; esac
echo "NEW_ROOT=$R8"

echo "=== SUPERSEDED EVIDENCE UNTOUCHED ==="
echo "V2R5_JOB=$(cat "$R5/status/training_job_id.txt" 2>&1)"
sha256sum "$R5/logs/training-217939.out" 2>&1
echo "V2R8_TRAINING_JOB=$(cat "$R7/status/training_job_id.txt" 2>&1)"
echo "CAPSULE_V3_MODE=$(stat -c %a "$CAP2")"
echo "CAPSULE_V4_MODE=$(stat -c %a "$CAP3")"

echo "=== PAYLOAD EXACT GATE ==="
A=$(sha256sum "$PAY/tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r9_formal_training.tar.gz" | cut -d" " -f1)
B=$(sha256sum "$PAY/bundle_manifest.sha256.json" | cut -d" " -f1)
C=$(sha256sum "$PAY/build_tukf09_455_a800_exclusive_hpc_bundle_v2r9.py" | cut -d" " -f1)
S=$(wc -c < "$PAY/tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r9_formal_training.tar.gz")
echo "ARCHIVE_SHA256=$A ARCHIVE_SIZE=$S"
test "$A" = "ba9241f0a70d8c2954de44e068c3e16352e718b64ff6edb25f095bee5482cf22" || { echo ARCHIVE_HASH_MISMATCH; exit 1; }
test "$S" = "9915703" || { echo ARCHIVE_SIZE_MISMATCH; exit 1; }
test "$B" = "dcae0fec9cec78be88c1a7c1904b734de6bbd1fd568f2fa6a6e85a5d2e8a88b7" || { echo MANIFEST_HASH_MISMATCH; exit 1; }
test "$C" = "3d6cae0daf74148262334f6437a6b434b49d4f2217f2b7c42ddd40856e9a0a03" || { echo BUILDER_HASH_MISMATCH; exit 1; }
echo PAYLOAD_EXACT_GATE_PASS

echo "=== EXCLUSIVE NEW ROOT RESERVATION ==="
if mkdir "$R8" 2>/dev/null; then echo NEW_ROOT_RESERVED; else echo NEW_ROOT_ALREADY_EXISTS; exit 1; fi
mkdir -p "$R8/logs" "$R8/status"

echo "=== EXTRACT AND STRICTLY VERIFY ==="
"$PY" -B "$PAY/build_tukf09_455_a800_exclusive_hpc_bundle_v2r9.py" --archive "$PAY/tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r9_formal_training.tar.gz" --extract-to "$R8/bundle" 2>&1
"$PY" -B "$PAY/build_tukf09_455_a800_exclusive_hpc_bundle_v2r9.py" --verify-extracted "$R8/bundle" 2>&1

echo "=== BOUND TO THE NEW CAPSULE, EXCLUSIVITY INTACT ==="
grep -n "SOURCE_ROOT=" "$R8/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r9/probe_gpu.slurm" 2>&1
grep -c "SBATCH --exclusive" "$R8/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r9/probe_gpu.slurm" 2>&1
grep -c "SBATCH --exclude" "$R8/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r9/probe_gpu.slurm" 2>&1
sha256sum "$R8/bundle/kalmannet/scripts/run_tukf09_455_neural_training_controller.py" 2>&1

echo "=== START THE RUNTIME INPUT DOWNLOAD, DETACHED ==="
SCRIPT="$R8/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r9/download_runtime_inputs_login.sh"
LOG="$R8/logs/offline-inputs-download.log"
setsid nohup bash "$SCRIPT" a20260904 < /dev/null > "$LOG" 2>&1 &
printf "pid=%s started=%s\n" "$!" "$(date -Is)" > "$R8/status/offline_inputs_download.launched"
echo "DOWNLOAD_LAUNCHED pid=$!"
sleep 8
du -sh "$R8"/offline_inputs_v2r9* 2>&1

echo TUKF09_455_A800_EXCLUSIVE_V2R9_DEPLOYED_DOWNLOAD_LAUNCHED_NO_JOB_SUBMITTED
