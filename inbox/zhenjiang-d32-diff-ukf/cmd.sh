#!/bin/bash
set -eo pipefail

PRECHECK_JOB_ID=216963
EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831_r3"
TRAINING_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
RUN_ROOT="${EVALUATION_ROOT}/run"
SCRIPT="${RUN_ROOT}/scripts/hpc/zhenjiang_d32_gru_differentiable_ukf_development_evaluation_formal_v1.slurm"
REGISTRY="${RUN_ROOT}/docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_DEVELOPMENT_EVALUATION_REGISTRY_R3.json"
ARCHIVE="${EVALUATION_ROOT}/bundles/zhenjiang_d32_gru_differentiable_ukf_dev_eval_20260831_r3.tar.gz"
JOB_RECORD="${EVALUATION_ROOT}/jobs/formal_array_job_id.txt"
EXPECTED_SCRIPT_BYTES=12421
EXPECTED_SCRIPT_SHA="7677dd63400f54e844f8f447423c3a327a9ea5f7e277ce4bb12ec67883f033de"
EXPECTED_REGISTRY_BYTES=15809
EXPECTED_REGISTRY_SHA="7ce4e50faac807bbf3557eb0befc6e05769bba263390b3a1be0a55b0097d5b04"
EXPECTED_ARCHIVE_BYTES=111275
EXPECTED_ARCHIVE_SHA="9258a4160bb435cb6bd79c60d6f7e43465a1ced6d67f4718eb367acb0596f2a1"

fatal() {
  echo "[FATAL] $1" >&2
  exit 1
}

verify_file() {
  local path="$1"
  local expected_bytes="$2"
  local expected_sha="$3"
  [ -f "${path}" ] || fatal "missing file: ${path}"
  [ ! -L "${path}" ] || fatal "symbolic file is forbidden: ${path}"
  [ "$(stat -c '%s' "${path}")" = "${expected_bytes}" ] || \
    fatal "byte count mismatch: ${path}"
  [ "$(sha256sum "${path}" | awk '{print $1}')" = "${expected_sha}" ] || \
    fatal "SHA-256 mismatch: ${path}"
}

[ -d "${EVALUATION_ROOT}" ] || fatal "revision-three evaluation root is absent"
[ ! -L "${EVALUATION_ROOT}" ] || fatal "revision-three evaluation root is symbolic"
[ -f "${EVALUATION_ROOT}/hpc_paths.env" ] || \
  fatal "revision-three path contract is absent"
verify_file "${SCRIPT}" "${EXPECTED_SCRIPT_BYTES}" "${EXPECTED_SCRIPT_SHA}"
verify_file "${REGISTRY}" "${EXPECTED_REGISTRY_BYTES}" "${EXPECTED_REGISTRY_SHA}"
verify_file "${ARCHIVE}" "${EXPECTED_ARCHIVE_BYTES}" "${EXPECTED_ARCHIVE_SHA}"
grep -qx "EVALUATION_ROOT=${EVALUATION_ROOT}" "${EVALUATION_ROOT}/hpc_paths.env" || \
  fatal "revision-three evaluation root contract changed"
grep -qx "REGISTRY_SHA256=${EXPECTED_REGISTRY_SHA}" "${EVALUATION_ROOT}/hpc_paths.env" || \
  fatal "revision-three registry contract changed"

grep -qx '#SBATCH --partition=hgpu2p' "${SCRIPT}" || \
  fatal "formal partition changed"
grep -qx '#SBATCH --exclude=ngu002' "${SCRIPT}" || \
  fatal "formal excluded-node contract changed"
grep -qx '#SBATCH --gres=gpu:1' "${SCRIPT}" || \
  fatal "formal graphics-processor contract changed"
grep -qx '#SBATCH --cpus-per-task=4' "${SCRIPT}" || \
  fatal "formal central-processing-unit contract changed"
grep -qx '#SBATCH --array=0-2%1' "${SCRIPT}" || \
  fatal "formal maximum-concurrency contract changed"

PRECHECK_ACCOUNTING="$(
  sacct -X -n -j "${PRECHECK_JOB_ID}" -P \
    --format=JobIDRaw,State,ExitCode |
    awk -F'|' -v job="${PRECHECK_JOB_ID}" '$1 == job {print $2 "|" $3}'
)"
[ "${PRECHECK_ACCOUNTING}" = "COMPLETED|0:0" ] || \
  fatal "precheck accounting gate failed: ${PRECHECK_ACCOUNTING}"

export PYTHONDONTWRITEBYTECODE=1
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
cd "${RUN_ROOT}"
export PYTHONPATH="${TRAINING_ROOT}/run/scripts/modeling:${RUN_ROOT}/scripts/analysis:${TRAINING_ROOT}/run/scripts/astronomical_tide:${TRAINING_ROOT}/run/third_party:${PYTHONPATH:-}"
for SEED in 17 29 43; do
  ATTEMPT="${EVALUATION_ROOT}/smoke/ZHD32-DUKF-DEV-EVAL-S${SEED}-V1/attempt_001"
  [ -d "${ATTEMPT}" ] || fatal "completed precheck attempt is absent: ${ATTEMPT}"
  [ ! -e "${ATTEMPT}.partial" ] || \
    fatal "partial precheck attempt remains: ${ATTEMPT}.partial"
  python -u scripts/analysis/zhenjiang_d32_gru_differentiable_ukf_development_evaluation_v1.py \
    --verify-output "${ATTEMPT}"
done

python - "${EVALUATION_ROOT}" "${REGISTRY}" <<'PY'
from pathlib import Path
import hashlib
import json
import sys


root = Path(sys.argv[1]).resolve()
registry_path = Path(sys.argv[2]).resolve()
registry_sha = hashlib.sha256(registry_path.read_bytes()).hexdigest()
registry = json.loads(registry_path.read_text())
normalization_contract = registry["normalization_identity_contract"]
zero = {
    "test_target_rows_read": 0,
    "test_target_values_loaded": 0,
    "test_target_values_parsed": 0,
}
for seed in (17, 29, 43):
    experiment = "ZHD32-DUKF-DEV-EVAL-S%d-V1" % seed
    attempt = root / "smoke" / experiment / "attempt_001"
    worker = json.loads((attempt / "worker_summary.json").read_text())
    data = json.loads((attempt / "data_identity.json").read_text())
    checkpoint = json.loads((attempt / "checkpoint_identity.json").read_text())
    run = json.loads((attempt / "run_identity.json").read_text())
    normalization = data.get("target_normalization_identity", {})
    expected = registry["experiments"][experiment]
    expected_run_sha = normalization_contract[
        "training_run_identity_sha256_by_seed"
    ][str(seed)]
    if (
        worker.get("status") != "completed_2023_development_smoke"
        or worker.get("completed_batches") != 2
        or worker.get("processed_base_sample_count") != 64
        or worker.get("block_count") != 1
        or worker.get("block_error_row_count") != 828
        or worker.get("block_analysis_row_count") != 6
        or worker.get("block_state_decay_row_count") != 138
        or worker.get("test_target_counters") != zero
        or data.get("test_target_counters") != zero
        or data.get("validation_base_sample_count") != 8046
        or data.get("last_loaded_target_time_beijing")
        != "2023-12-31T23:00:00+08:00"
        or data.get("source_training_data_identity_sha256")
        != normalization_contract["legacy_training_data_identity_sha256"]
        or data.get("source_training_run_identity_sha256") != expected_run_sha
        or normalization.get("verification_method")
        != normalization_contract["verification_method"]
        or normalization.get("source_training_target_mean_present") is not False
        or normalization.get("source_training_data_identity_sha256")
        != normalization_contract["legacy_training_data_identity_sha256"]
        or normalization.get("source_training_run_identity_sha256")
        != expected_run_sha
        or normalization.get("station_order")
        != normalization_contract["station_order"]
        or normalization.get("target_mean_float32_bits")
        != normalization_contract["target_mean_float32_bits"]
        or normalization.get("target_standard_deviation_float32_bits")
        != normalization_contract["target_standard_deviation_float32_bits"]
        or run.get("registry_sha256") != registry_sha
        or checkpoint.get("best_checkpoint_sha256")
        != expected["best_checkpoint_sha256"]
        or checkpoint.get("only_adapter_state_dict_loaded") is not True
        or checkpoint.get("optimizer_state_loaded") is not False
        or checkpoint.get("random_state_loaded") is not False
    ):
        raise SystemExit(
            "revision-three formal-submission precheck gate failed for seed %d"
            % seed
        )
print("REVISION_THREE_FORMAL_SUBMISSION_PRECHECK_GATE=PASS")
PY

for SEED in 17 29 43; do
  ATTEMPT="${EVALUATION_ROOT}/workers/ZHD32-DUKF-DEV-EVAL-S${SEED}-V1/attempt_001"
  [ ! -e "${ATTEMPT}" ] || fatal "formal worker attempt already exists: ${ATTEMPT}"
  [ ! -e "${ATTEMPT}.partial" ] || \
    fatal "formal worker partial attempt already exists: ${ATTEMPT}.partial"
done
SUMMARY="${EVALUATION_ROOT}/summary/ZHD32-DUKF-DEV-EVAL-SUMMARY-V1/attempt_001"
[ ! -e "${SUMMARY}" ] || fatal "formal summary already exists"
[ ! -e "${SUMMARY}.partial" ] || fatal "formal summary partial already exists"
[ ! -e "${JOB_RECORD}" ] || fatal "formal array job record already exists"
[ ! -e "${JOB_RECORD}.partial" ] || fatal "formal array partial job record exists"

EXISTING="$(squeue -h -u "${USER}" -n zhd32_dukf_dev_eval -o '%i|%T|%j')"
[ -z "${EXISTING}" ] || fatal "formal evaluation is already queued: ${EXISTING}"

JOB_ID="$(sbatch --parsable "${SCRIPT}")"
[ -n "${JOB_ID}" ] || fatal "scheduler returned no formal array job identifier"
JOB_ID="${JOB_ID%%;*}"
{
  printf 'job_id=%s\n' "${JOB_ID}"
  printf 'submitted_at=%s\n' "$(date -Is)"
  printf 'precheck_job_id=%s\n' "${PRECHECK_JOB_ID}"
  printf 'script_sha256=%s\n' "${EXPECTED_SCRIPT_SHA}"
  printf 'registry_sha256=%s\n' "${EXPECTED_REGISTRY_SHA}"
  printf 'array=%s\n' '0-2%1'
  printf 'excluded_node=%s\n' 'ngu002'
} > "${JOB_RECORD}.partial"
chmod 0400 "${JOB_RECORD}.partial"
mv "${JOB_RECORD}.partial" "${JOB_RECORD}"

echo "REVISION_THREE_FORMAL_ARRAY_SUBMISSION_STATUS=PASS"
echo "REVISION_THREE_FORMAL_ARRAY_JOB_ID=${JOB_ID}"
cat "${JOB_RECORD}"
squeue -j "${JOB_ID}" -o '%i|%j|%T|%P|%N|%M|%l|%R'
scontrol show job -o "${JOB_ID}" || true
