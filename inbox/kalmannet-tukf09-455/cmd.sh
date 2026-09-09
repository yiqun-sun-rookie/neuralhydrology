#!/bin/bash
# TUKF09-455: deploy the v2r14 bundle into a fresh remote root and start the offline
# runtime input download. Submits no job. Touches no superseded root and no earlier capsule.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909
PRIOR=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r13_20260909
CAPSULE=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v7_20260909
PAY=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-tukf09-455/v2r14
ARCHIVE=tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r14_formal_training.tar.gz
echo "TIME=$(date -Is)"

echo "=== SCOPE GUARD: SUPERSEDED EVIDENCE UNTOUCHED ==="
echo "V2R10_TRAINING_JOB=$(cat /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r10_20260904/status/training_job_id.txt 2>/dev/null)"
sha256sum /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r10_20260904/logs/training-220663.err 2>&1 | head -1
for c in v2 v3 v4 v5 v6 v7; do d=$(ls -d /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_${c}_2026* 2>/dev/null | head -1); echo "CAPSULE_${c}_MODE=$(stat -c %a "$d" 2>/dev/null)"; done
test -d "$CAPSULE" || { echo CAPSULE_V7_MISSING; exit 10; }

echo "=== THE V2R13 ROOT IS FROZEN AND STAYS FROZEN ==="
echo "V2R13_PREPARATION_FAILED_MARKER=$(test -f "$PRIOR/status/PREPARATION_FAILED.json" && echo present || echo absent)"
echo "V2R13_PREP_JOB=$(cat "$PRIOR/status/preparation_job_id.txt" 2>/dev/null)"
grep -n "get_device_capability" "$PRIOR/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r13/probe_gpu.slurm" 2>/dev/null | head -2

echo "=== PAYLOAD EXACT GATE ==="
test -f "$PAY/$ARCHIVE" || { echo PAYLOAD_MISSING; exit 11; }
ACT_SHA=$(sha256sum "$PAY/$ARCHIVE" | cut -d" " -f1); ACT_SIZE=$(stat -c %s "$PAY/$ARCHIVE")
echo "ARCHIVE_SHA256=$ACT_SHA ARCHIVE_SIZE=$ACT_SIZE"
if [ "$ACT_SHA" != "9b76bce8578516992945ddd8144690fab50b477af8230adc181f8e176feb4bb4" ] || [ "$ACT_SIZE" != "9924435" ]; then
  echo PAYLOAD_EXACT_GATE_FAIL; exit 12
fi
echo PAYLOAD_EXACT_GATE_PASS

echo "=== EXCLUSIVE NEW ROOT RESERVATION ==="
if [ -e "$ROOT" ]; then echo NEW_ROOT_ALREADY_EXISTS; exit 13; fi
mkdir "$ROOT" && mkdir "$ROOT/logs" "$ROOT/status" && echo NEW_ROOT_RESERVED

echo "=== EXTRACT AND STRICTLY VERIFY ==="
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo CONDA_FAILED; exit 14; }
python -X utf8 "$PAY/build_tukf09_455_a800_exclusive_hpc_bundle_v2r14.py" \
  --archive "$PAY/$ARCHIVE" --extract-to "$ROOT/bundle"
python -X utf8 "$ROOT/bundle/kalmannet/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2r14.py" \
  --verify-extracted "$ROOT/bundle"

echo "=== THE LINE THAT KILLED V2R13, AS DEPLOYED ==="
P="$ROOT/bundle/kalmannet"
G="$P/hpc/tukf09_455_basin_revision_a800_exclusive_v2r14/probe_gpu.slurm"
S="$P/hpc/tukf09_455_basin_revision_a800_exclusive_v2r14/submit_training_gpu.slurm"
grep -n "get_device_capability\|get_device_name\|device_count" "$G"
echo "STALE_CAPABILITY_LITERALS=$(grep -c "(8, 0)" "$G" || true)"
if [ "$(grep -c "== (8, 6)" "$G" || true)" != "1" ]; then echo CAPABILITY_LINE_WRONG; exit 16; fi
echo CAPABILITY_LINE_OK

echo "=== BINDINGS THIS REVISION MUST HAVE ==="
echo "CAPSULE_BINDING=$(grep -c "training_source_capsule_v7_20260909" "$G")"
echo "EXCLUSIVE_DIRECTIVES=$(grep -c -- "--exclusive" "$S" || true)"
echo "PARTITION_LINE=$(grep -- "^#SBATCH -p" "$S")"
echo "GRES_LINE=$(grep -- "--gres" "$S")"
echo "CPUS_LINE=$(grep -- "--cpus-per-task" "$S")"
echo "WALLTIME_LINE=$(grep -- "^#SBATCH -t" "$S")"
echo "POPULATION_FIX_PRESENT=$(grep -c "_ordered_basin_compact_digest" "$P/scripts/run_tukf09_455_neural_training.py")"
sha256sum "$P/scripts/run_tukf09_455_neural_training.py" "$P/scripts/run_tukf09_455_neural_training_controller.py" 2>&1
python -X utf8 - '$P' <<'PY'
import json, sys
root = sys.argv[1]
cfg = json.load(open(root + "/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r14.json"))
sci, run, slurm, route = cfg["scientific_identity"], cfg["required_hpc_runtime"], cfg["slurm"], cfg["execution_route"]
print("MIGRATION_PIN=" + sci["filter_migration_final_manifest"]["sha256"])
print("ADMISSION_PIN=" + sci["original_training_admission"]["file_sha256"])
print("CARD=" + run["cuda_device_name"], "CAPABILITY=" + str(run["cuda_compute_capability"]),
      "DEVICES=" + str(run["cuda_device_count"]))
print("PARTITION=" + slurm["partition"], "GPUS=" + str(slurm["gpus"]), "CPUS=" + str(slurm["cpus_per_task"]),
      "EXCLUSIVE=" + str(slurm["exclusive_node"]))
print("PARALLELISM=" + str(route["neural_model_parallelism"]), "WAVES=" + str(route["neural_execution_waves"]))
PY

echo "=== START THE RUNTIME INPUT DOWNLOAD, DETACHED ==="
# The attempt identifier is required by the downloader and was omitted last round.
D="$P/hpc/tukf09_455_basin_revision_a800_exclusive_v2r14/download_runtime_inputs_login.sh"
test -f "$D" || { echo DOWNLOADER_MISSING; exit 15; }
touch "$ROOT/status/offline_inputs_download.lock"
nohup bash "$D" v2r14a > "$ROOT/logs/offline-inputs-download.out" 2>&1 &
echo "DOWNLOAD_LAUNCHED attempt=v2r14a pid=$!" | tee "$ROOT/status/offline_inputs_download.launched"
sleep 25
echo "--- first 25 seconds of the download log ---"
tail -n 15 "$ROOT/logs/offline-inputs-download.out" 2>/dev/null || true

echo TUKF09_455_V2R14_DEPLOYED_NO_JOB_SUBMITTED
