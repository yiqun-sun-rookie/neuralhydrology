#!/bin/bash
# TUKF09-455: deploy the v2r13 bundle into a fresh remote root and start the offline
# runtime input download. Submits no training job. Touches no superseded root and no
# earlier capsule.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r13_20260909
CAPSULE=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v7_20260909
PAY=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-tukf09-455/v2r13
ARCHIVE=tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r13_formal_training.tar.gz
echo "TIME=$(date -Is)"

echo "=== SCOPE GUARD: SUPERSEDED EVIDENCE UNTOUCHED ==="
echo "V2R10_TRAINING_JOB=$(cat /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r10_20260904/status/training_job_id.txt 2>/dev/null)"
sha256sum /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r10_20260904/logs/training-220663.err 2>&1 | head -1
for c in v2 v3 v4 v5 v6; do d=$(ls -d /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_${c}_2026* 2>/dev/null | head -1); echo "CAPSULE_${c}_MODE=$(stat -c %a "$d" 2>/dev/null)"; done
test -d "$CAPSULE" || { echo CAPSULE_V6_MISSING; exit 10; }

echo "=== PAYLOAD EXACT GATE ==="
test -f "$PAY/$ARCHIVE" || { echo PAYLOAD_MISSING; exit 11; }
ACT_SHA=$(sha256sum "$PAY/$ARCHIVE" | cut -d" " -f1); ACT_SIZE=$(stat -c %s "$PAY/$ARCHIVE")
echo "ARCHIVE_SHA256=$ACT_SHA ARCHIVE_SIZE=$ACT_SIZE"
if [ "$ACT_SHA" != "ea009bfa79bb13969dc9578866c77b72f3cf145695c8be48119a416dee670684" ] || [ "$ACT_SIZE" != "9923501" ]; then
  echo PAYLOAD_EXACT_GATE_FAIL; exit 12
fi
echo PAYLOAD_EXACT_GATE_PASS

echo "=== EXCLUSIVE NEW ROOT RESERVATION ==="
if [ -e "$ROOT" ]; then echo NEW_ROOT_ALREADY_EXISTS; exit 13; fi
mkdir "$ROOT" && mkdir "$ROOT/logs" "$ROOT/status" && echo NEW_ROOT_RESERVED

echo "=== EXTRACT AND STRICTLY VERIFY ==="
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo CONDA_FAILED; exit 14; }
python -X utf8 "$PAY/build_tukf09_455_a800_exclusive_hpc_bundle_v2r13.py" \
  --archive "$PAY/$ARCHIVE" --extract-to "$ROOT/bundle"
python -X utf8 "$ROOT/bundle/kalmannet/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2r13.py" \
  --verify-extracted "$ROOT/bundle"

echo "=== BINDINGS THIS REVISION MUST HAVE ==="
P="$ROOT/bundle/kalmannet"
S="$P/hpc/tukf09_455_basin_revision_a800_exclusive_v2r13/submit_training_gpu.slurm"
echo "CAPSULE_BINDING=$(grep -c "training_source_capsule_v7_20260909" "$P/hpc/tukf09_455_basin_revision_a800_exclusive_v2r13/probe_gpu.slurm")"
echo "EXCLUSIVE_DIRECTIVES=$(grep -c -- "--exclusive" "$S" || true)"
echo "GRES_LINE=$(grep -- "--gres" "$S")"
echo "CPUS_LINE=$(grep -- "--cpus-per-task" "$S")"
echo "WALLTIME_LINE=$(grep -- "^#SBATCH -t" "$S")"
echo "EXCLUDE_DIRECTIVES=$(grep -c -- "--exclude" "$S" || true)"
echo "POPULATION_FIX_PRESENT=$(grep -c "_ordered_basin_compact_digest" "$P/scripts/run_tukf09_455_neural_training.py")"
sha256sum "$P/scripts/run_tukf09_455_neural_training.py" "$P/scripts/run_tukf09_455_neural_training_controller.py" 2>&1
echo "MIGRATION_PIN=$(python -X utf8 -c "import json;print(json.load(open('$P/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r13.json'))['scientific_identity']['filter_migration_final_manifest']['sha256'])")"

echo "=== START THE RUNTIME INPUT DOWNLOAD, DETACHED ==="
D="$P/hpc/tukf09_455_basin_revision_a800_exclusive_v2r13/download_runtime_inputs_login.sh"
test -f "$D" || { echo DOWNLOADER_MISSING; exit 15; }
touch "$ROOT/status/offline_inputs_download.lock"
nohup bash "$D" > "$ROOT/logs/offline-inputs-download.out" 2>&1 &
echo "DOWNLOAD_LAUNCHED pid=$!" | tee "$ROOT/status/offline_inputs_download.launched"

echo TUKF09_455_V2R12_DEPLOYED_NO_JOB_SUBMITTED
