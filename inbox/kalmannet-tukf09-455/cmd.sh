#!/bin/bash
# TUKF09-455: read the v2r14 bindings and launch the offline runtime input download.
# Seq 180 already reserved this root and verified the bundle. Submits no job.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909
P="$ROOT/bundle/kalmannet"
echo "TIME=$(date -Is)"

echo "=== THE ROOT SEQ 180 LEFT BEHIND ==="
test -d "$ROOT" || { echo ROOT_MISSING; exit 10; }
test -d "$P" || { echo BUNDLE_MISSING; exit 11; }
ls -la "$ROOT" "$ROOT/status" "$ROOT/logs"
echo "OFFLINE_INPUTS_PRESENT=$(test -d "$ROOT/offline_inputs_v2r14" && echo yes || echo no)"

echo "=== BINDINGS, READ PROPERLY THIS TIME ==="
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo CONDA_FAILED; exit 12; }
python -X utf8 - "$P" <<'PYEOF'
import json, sys
root = sys.argv[1]
cfg = json.load(open(root + "/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r14.json"))
sci = cfg["scientific_identity"]
run = cfg["required_hpc_runtime"]
slurm = cfg["slurm"]
route = cfg["execution_route"]
print("AUTHORIZATION_PIN=" + sci["all_scope_authorization"]["sha256"])
print("MIGRATION_PIN=" + sci["filter_migration_final_manifest"]["sha256"])
print("ADMISSION_PIN=" + sci["original_training_admission"]["file_sha256"])
print("ADMISSION_RECORD_PIN=" + sci["original_training_admission"]["record_sha256"])
print("INSTALLATION_PIN=" + sci["local_filter_installation_final_manifest"]["sha256"])
print("CARD=" + run["cuda_device_name"] + " CAPABILITY=" + str(run["cuda_compute_capability"]) + " DEVICES=" + str(run["cuda_device_count"]))
print("PARTITION=" + slurm["partition"] + " GPUS=" + str(slurm["gpus"]) + " CPUS=" + str(slurm["cpus_per_task"]) + " EXCLUSIVE=" + str(slurm["exclusive_node"]))
print("PARALLELISM=" + str(route["neural_model_parallelism"]) + " WAVES=" + str(route["neural_execution_waves"]))
print("CAPSULE=" + cfg["training_source_capsule"]["root"].rsplit("/", 1)[-1])
PYEOF

echo "=== WHAT THE FOUR-CARD PARTITION LOOKS LIKE RIGHT NOW ==="
sinfo -p hgpu4 -N -O NodeHost,StateLong,Gres,GresUsed,CPUsState 2>&1 | head -8

echo "=== LAUNCH THE OFFLINE RUNTIME INPUT DOWNLOAD, DETACHED ==="
D="$P/hpc/tukf09_455_basin_revision_a800_exclusive_v2r14/download_runtime_inputs_login.sh"
test -f "$D" || { echo DOWNLOADER_MISSING; exit 13; }
nohup bash "$D" v2r14a > "$ROOT/logs/offline-inputs-download.out" 2>&1 &
echo "DOWNLOAD_LAUNCHED attempt=v2r14a pid=$!" | tee "$ROOT/status/offline_inputs_download.launched"
sleep 45
echo "--- first 45 seconds of the download log ---"
tail -n 20 "$ROOT/logs/offline-inputs-download.out" 2>/dev/null || true
echo "PENDING_BYTES=$(du -sb "$ROOT/offline_inputs_v2r14.pending.v2r14a" 2>/dev/null | cut -f1)"

echo TUKF09_455_V2R14_DOWNLOAD_LAUNCHED_NO_JOB_SUBMITTED
