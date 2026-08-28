#!/bin/bash
set -eo pipefail
umask 077

ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
PROJECT_ROOT="${ROOT}/run"
INPUT_DIR="${ROOT}/inputs/pre2024-v1"
SMOKE_ATTEMPT="${ROOT}/runs/smoke/ZHD32-DUKF-HPC-SMOKE-V1/attempt_001"
SMOKE_JOB_FILE="${ROOT}/jobs/smoke_job_id.txt"
FORMAL_SCRIPT="${PROJECT_ROOT}/scripts/hpc/zhenjiang_d32_gru_differentiable_ukf_formal_v1.slurm"
FORMAL_JOB_FILE="${ROOT}/jobs/formal_job_id.txt"

fatal() {
  echo "[FATAL] $1"
  exit 1
}

[ -f "${SMOKE_JOB_FILE}" ] || fatal "smoke job identity is absent"
smoke_job_id="$(tr -d '\r\n' < "${SMOKE_JOB_FILE}")"
[[ "${smoke_job_id}" =~ ^[0-9]+$ ]] || fatal "smoke job identity is invalid"
smoke_row="$(
  sacct -j "${smoke_job_id}" -n -P \
    --format=JobIDRaw,State,ExitCode,ElapsedRaw,NodeList | \
    awk -F'|' -v id="${smoke_job_id}" '$1 == id {print; exit}'
)"
[ -n "${smoke_row}" ] || fatal "smoke scheduler row is absent"
IFS='|' read -r observed_job smoke_state smoke_exit smoke_elapsed smoke_node <<< "${smoke_row}"
[ "${observed_job}" = "${smoke_job_id}" ] || fatal "smoke scheduler identity changed"
[ "${smoke_state}" = "COMPLETED" ] || fatal "smoke scheduler state is not completed"
[ "${smoke_exit}" = "0:0" ] || fatal "smoke scheduler exit is not zero"
[ "${smoke_node}" != "ngu002" ] || fatal "smoke used the excluded node"
[[ "${smoke_elapsed}" =~ ^[0-9]+$ ]] || fatal "smoke elapsed seconds is invalid"

[ -f "${FORMAL_SCRIPT}" ] || fatal "formal array script is absent"
[ ! -L "${FORMAL_SCRIPT}" ] || fatal "formal array script is a symbolic link"
[ "$(sha256sum "${FORMAL_SCRIPT}" | awk '{print $1}')" = \
  "5df495917445542bcf8b2a08855c7ed83e32a773f3bb9767c1b53af147bbdd77" ] || \
  fatal "formal array script identity changed"
bash -n "${FORMAL_SCRIPT}"
[ -f "${ROOT}/hpc_paths.env" ] || fatal "hpc_paths.env is absent"
[ "$(cat "${ROOT}/hpc_paths.env")" = "INPUT_DIR=${INPUT_DIR}" ] || \
  fatal "isolated input contract changed"
[ "$(readlink -f "${INPUT_DIR}")" = "${INPUT_DIR}" ] || \
  fatal "isolated input canonical path changed"
[ ! -L "${INPUT_DIR}" ] || fatal "isolated input is a symbolic link"
[ -f "${INPUT_DIR}/pre2024_input_manifest.json" ] || fatal "pre-2024 manifest is absent"
[ ! -e "${FORMAL_JOB_FILE}" ] || fatal "formal job identity already exists"
[ ! -e "${FORMAL_JOB_FILE}.partial" ] || fatal "partial formal job identity exists"

for experiment_id in ZHD32-DUKF-S17-V1 ZHD32-DUKF-S29-V1 ZHD32-DUKF-S43-V1; do
  formal_attempt="${ROOT}/runs/formal/${experiment_id}/attempt_001"
  [ ! -e "${formal_attempt}" ] || fatal "formal attempt already exists: ${formal_attempt}"
  [ ! -e "${formal_attempt}.partial" ] || fatal "partial formal attempt exists: ${formal_attempt}.partial"
done
existing="$(
  squeue -u "${USER}" -h -o '%i|%j|%T' | \
    awk -F'|' '$2 == "zhd32-dukf-formal" {print}'
)"
[ -z "${existing}" ] || fatal "same-name formal job already exists: ${existing}"

export PYTHONDONTWRITEBYTECODE=1
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
cd "${PROJECT_ROOT}"
python -u scripts/modeling/zhenjiang_d32_gru_differentiable_ukf_runner_v1.py \
  --verify-output "${SMOKE_ATTEMPT}"

python - "${SMOKE_ATTEMPT}" "${INPUT_DIR}" "${smoke_elapsed}" <<'PY'
from pathlib import Path
import csv
import json
import math
import sys

attempt = Path(sys.argv[1]).resolve()
input_dir = Path(sys.argv[2]).resolve()
elapsed = int(sys.argv[3])

def require(condition, message):
    if not condition:
        raise SystemExit(message)

def document(name):
    return json.loads((attempt / name).read_text(encoding="utf-8"))

completion = document("completion_manifest.json")
require(completion.get("status") == "technical_pass", "smoke completion status changed")
preflight = document("gpu_technical_preflight.json")
require(preflight.get("status") == "pass_technical_only", "smoke preflight status changed")
require(preflight.get("base_batch_size") == 32, "smoke batch size changed")
require(preflight.get("gradient_scalar_count") == 38, "smoke gradient count changed")
require(preflight.get("nonfinite_gradient_count") == 0, "smoke gradient became nonfinite")
require(preflight.get("zero_gradient_count") == 0, "smoke gradient became zero")
require(preflight.get("spectral_floor_mask") == [False, True], "smoke spectral-floor mask changed")
require(preflight.get("backbone_state_sha256_before") == preflight.get("backbone_state_sha256_after"), "smoke preflight changed backbone")

data = document("data_identity.json")
zero_counters = {
    "test_target_rows_read": 0,
    "test_target_values_parsed": 0,
    "test_target_values_loaded": 0,
}
require(data.get("input_directory") == str(input_dir), "smoke input directory changed")
require(data.get("training_base_sample_count") == 46182, "training sample count changed")
require(data.get("validation_base_sample_count") == 8046, "validation sample count changed")
require(data.get("last_loaded_target_time_beijing") == "2023-12-31T23:00:00+08:00", "last target time changed")
require(data.get("test_target_counters") == zero_counters, "later-target counter changed")
require(len(data.get("input_content_identities", [])) == 13, "input identity count changed")

run = document("run_identity.json")
environment = run.get("environment", {})
require(run.get("completion_status") == "technical_pass", "smoke run status changed")
require(run.get("authorization") == {"held_out_target_access": False, "scientific_conclusion": False, "paid_compute": True}, "smoke authorization changed")
require(environment.get("deterministic_algorithms_enabled") is True, "deterministic mode changed")
require(environment.get("cuda_matmul_allow_tf32") is False, "matrix TensorFloat-32 is enabled")
require(environment.get("cudnn_allow_tf32") is False, "cuDNN TensorFloat-32 is enabled")

selection = document("selection_validation_summary.json")
require(selection.get("status") == "technical_pass", "smoke selection status changed")
require(selection.get("held_out_target_access") is False, "held-out target access changed")
require(selection.get("scientific_conclusion_authorized") is False, "scientific boundary changed")
require(selection.get("test_target_counters") == zero_counters, "selection target counter changed")
require(selection.get("backbone_state_sha256_before") == selection.get("backbone_state_sha256_after"), "smoke training changed backbone")

with (attempt / "training_history.csv").open("r", encoding="utf-8", newline="") as handle:
    rows = list(csv.DictReader(handle))
require(len(rows) == 1, "smoke epoch count changed")
epoch_seconds = float(rows[0]["epoch_seconds"])
preflight_seconds = float(preflight["forward_backward_seconds"])
require(math.isfinite(epoch_seconds) and epoch_seconds > 0.0, "smoke epoch time is invalid")
require(math.isfinite(preflight_seconds) and preflight_seconds > 0.0, "preflight time is invalid")
seconds_per_batch = max(epoch_seconds / 4.0, preflight_seconds)
formal_batches = math.ceil(46182 / 32) + math.ceil(8046 / 32)
single_hours_with_margin = (
    max(0.0, elapsed - epoch_seconds)
    + seconds_per_batch * formal_batches * 20
) * 1.25 / 3600.0
require(single_hours_with_margin <= 72.0, "formal wall-time projection exceeds 72 hours")
print(
    "FORMAL_SUBMISSION_GATE=PASS"
    f"|single_hours_with_margin={single_hours_with_margin:.6f}"
    f"|three_serial_hours_with_margin={3.0 * single_hours_with_margin:.6f}"
)
PY

set +e
receipt="$(sbatch "${FORMAL_SCRIPT}" 2>&1)"
submit_rc=$?
set -e
printf '%s\n' "${receipt}"
submission_lines="$(
  printf '%s\n' "${receipt}" | grep -E '^Submitted batch job [0-9]+$' || true
)"
line_count="$(
  printf '%s\n' "${submission_lines}" | sed '/^$/d' | wc -l | tr -d '[:space:]'
)"
[ "${line_count}" = "1" ] || fatal "formal receipt did not contain exactly one accepted job"
job_id="${submission_lines##* }"
[[ "${job_id}" =~ ^[0-9]+$ ]] || fatal "formal job identifier is invalid"
printf '%s\n' "${job_id}" > "${FORMAL_JOB_FILE}.partial"
chmod 0400 "${FORMAL_JOB_FILE}.partial"
mv "${FORMAL_JOB_FILE}.partial" "${FORMAL_JOB_FILE}"
[ "${submit_rc}" -eq 0 ] || fatal "formal job was submitted but sbatch returned nonzero"

echo "FORMAL_ARRAY_SUBMISSION=ACCEPTED"
echo "FORMAL_ARRAY_JOB_ID=${job_id}"
squeue -j "${job_id}" -h -o '%i|%P|%j|%T|%M|%l|%R' || true
