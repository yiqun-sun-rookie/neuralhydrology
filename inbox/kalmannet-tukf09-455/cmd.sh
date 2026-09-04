#!/bin/bash
# TUKF09-455 v2r8: deploy the bundle bound to training source capsule v3, then run
# the whole preparation in one go if the runtime inputs land. Nothing scientific moves:
# the population, periods, model, seeds, budget, mask, metric, threshold and decision
# order are untouched, the whole-node exclusive requirement and the compute-process
# gate are unchanged, and no training job is submitted here.

set -o pipefail

R8=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r8_20260904
R7=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r7_20260904
R5=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
CAP3=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v3_20260904
CAP2=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v2_20260901
PAY="$PWD/payload/kalmannet-tukf09-455/a800-exclusive-v2r8-capsule-identity"
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

echo "TIME=$(date -Is)"
echo "=== SCOPE GUARD ==="
case "$R8" in *v2r4*|*v2r5*|*v2r6*|*v2r7*|*capsule*) echo SCOPE_GUARD_FAILED; exit 1;; esac
echo "NEW_ROOT=$R8"

echo "=== SUPERSEDED EVIDENCE UNTOUCHED ==="
echo "V2R5_JOB=$(cat "$R5/status/training_job_id.txt" 2>&1)"
sha256sum "$R5/logs/training-217939.out" 2>&1
echo "V2R7_MARKER=$(cat "$R7/status/PREPARATION_FAILED.json" 2>&1)"
echo "CAPSULE_V2_MODE=$(stat -c %a "$CAP2")"
echo "CAPSULE_V3_MODE=$(stat -c %a "$CAP3")"

echo "=== PAYLOAD EXACT GATE ==="
A=$(sha256sum "$PAY/tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r8_formal_training.tar.gz" | cut -d" " -f1)
B=$(sha256sum "$PAY/bundle_manifest.sha256.json" | cut -d" " -f1)
C=$(sha256sum "$PAY/build_tukf09_455_a800_exclusive_hpc_bundle_v2r8.py" | cut -d" " -f1)
S=$(wc -c < "$PAY/tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r8_formal_training.tar.gz")
echo "ARCHIVE_SHA256=$A ARCHIVE_SIZE=$S"
test "$A" = "cf9cb1a59e6b4604596f765b29024056af649abe85d5d716b45f7ff865b4a8fa" || { echo ARCHIVE_HASH_MISMATCH; exit 1; }
test "$S" = "9914079" || { echo ARCHIVE_SIZE_MISMATCH; exit 1; }
test "$B" = "59f8cdde44aa31e8158e9ccb33dc144800b916430a8aabb592e27a17b3e05907" || { echo MANIFEST_HASH_MISMATCH; exit 1; }
test "$C" = "314355bf9d507493200d13a6db9c7a9686353ca84a41e29c6cbca9ae9b048f5e" || { echo BUILDER_HASH_MISMATCH; exit 1; }
echo PAYLOAD_EXACT_GATE_PASS

echo "=== EXCLUSIVE NEW ROOT RESERVATION ==="
if mkdir "$R8" 2>/dev/null; then echo NEW_ROOT_RESERVED; else echo NEW_ROOT_ALREADY_EXISTS; exit 1; fi
mkdir -p "$R8/logs" "$R8/status"

echo "=== EXTRACT AND STRICTLY VERIFY ==="
"$PY" -B "$PAY/build_tukf09_455_a800_exclusive_hpc_bundle_v2r8.py" --archive "$PAY/tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r8_formal_training.tar.gz" --extract-to "$R8/bundle" 2>&1
"$PY" -B "$PAY/build_tukf09_455_a800_exclusive_hpc_bundle_v2r8.py" --verify-extracted "$R8/bundle" 2>&1

echo "=== BOUND TO THE NEW CAPSULE, EXCLUSIVITY INTACT ==="
grep -n "SOURCE_ROOT=" "$R8/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r8/probe_gpu.slurm" 2>&1
grep -c "SBATCH --exclusive" "$R8/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r8/probe_gpu.slurm" 2>&1
grep -c "SBATCH --exclude" "$R8/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r8/probe_gpu.slurm" 2>&1
sha256sum "$R8/bundle/kalmannet/scripts/run_tukf09_455_neural_training_controller.py" 2>&1

echo "=== START THE RUNTIME INPUT DOWNLOAD, DETACHED ==="
SCRIPT="$R8/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r8/download_runtime_inputs_login.sh"
LOG="$R8/logs/offline-inputs-download.log"
setsid nohup bash "$SCRIPT" a20260904 < /dev/null > "$LOG" 2>&1 &
printf "pid=%s started=%s\n" "$!" "$(date -Is)" > "$R8/status/offline_inputs_download.launched"
echo "DOWNLOAD_LAUNCHED pid=$!"
sleep 8
du -sh "$R8"/offline_inputs_v2r8* 2>&1

echo TUKF09_455_A800_EXCLUSIVE_V2R8_DEPLOYED_DOWNLOAD_LAUNCHED_NO_JOB_SUBMITTED
