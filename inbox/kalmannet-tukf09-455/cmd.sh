#!/bin/bash
# Submit exactly one isolated A800 preparation job after the package allocation probe passed.
set -o pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2_20260831
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
SOURCE_ROOT=/data1/home/sunyiq/neuralhydrology/data/camels_us
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
STAGED_ROOT="${PROJECT_ROOT}/G:/github/pycharm/projects/neuralhydrology/data/camels_us"
PREPARE_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2/probe_gpu.slurm"
PREPARE_SCRIPT_SHA=ec25ba56c16226ddbccc5c2d58459daccefc8d165e4216cb897703bc79223ac8
STAGE_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2/stage_and_train.py"
STAGE_SCRIPT_SHA=bd97de1c69e199f798f79021d1eddb8bd778389ca541f7714578c5c7a48ba6ef
ALLOCATION_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2/allocation_probe.slurm"
ALLOCATION_SCRIPT_SHA=0dbee5218b46fb31336e779c6ceb86d1904e3549f22b9bfe5b60ba8bbb02cbb7
EXECUTION_CONFIG="${PROJECT_ROOT}/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2.json"
EXECUTION_CONFIG_SHA=c19d48f679d1eef0c3a21ce67c41a800980d1f51a00360e8adb5d8d9d1d71221
DEPLOYMENT_SUMMARY="${ROOT}/status/deployment_summary.json"
DEPLOYMENT_SUMMARY_SHA=5b7452d455f2a95b35fdfbd14b0ae4ef9746df7e75743cd89fed93e87603025a
ALLOCATION_JOB_ID=217143
ALLOCATION_JOB_ID_FILE="${ROOT}/status/allocation_probe_job_id.txt"
ALLOCATION_STDOUT="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.out"
ALLOCATION_STDOUT_SHA=0c2bc6e662437b0e392147e87c52366808d915b3f1d5bd928f709a65c4e7d383
ALLOCATION_STDERR="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.err"
EMPTY_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
JOB_NAME=tukf09-455-a800-v2-prepare
JOB_ID_FILE="${ROOT}/status/preparation_job_id.txt"

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== FROZEN DEPLOYMENT AND ALLOCATION GATES ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${SOURCE_ROOT}" "${ROOT}/logs" "${ROOT}/status"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing, linked, or irregular: ${item}"
done
for item in \
  "${PREPARE_SCRIPT}" \
  "${STAGE_SCRIPT}" \
  "${ALLOCATION_SCRIPT}" \
  "${EXECUTION_CONFIG}" \
  "${DEPLOYMENT_SUMMARY}" \
  "${ALLOCATION_JOB_ID_FILE}" \
  "${ALLOCATION_STDOUT}" \
  "${ALLOCATION_STDERR}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "required file missing, linked, or irregular: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "required file hard-link count changed: ${item}"
done
[[ "$(sha256sum "${PREPARE_SCRIPT}" | awk '{print $1}')" = "${PREPARE_SCRIPT_SHA}" ]] || fail "preparation wrapper hash mismatch"
[[ "$(sha256sum "${STAGE_SCRIPT}" | awk '{print $1}')" = "${STAGE_SCRIPT_SHA}" ]] || fail "preparation controller hash mismatch"
[[ "$(sha256sum "${ALLOCATION_SCRIPT}" | awk '{print $1}')" = "${ALLOCATION_SCRIPT_SHA}" ]] || fail "allocation wrapper hash mismatch"
[[ "$(sha256sum "${EXECUTION_CONFIG}" | awk '{print $1}')" = "${EXECUTION_CONFIG_SHA}" ]] || fail "execution config hash mismatch"
[[ "$(sha256sum "${DEPLOYMENT_SUMMARY}" | awk '{print $1}')" = "${DEPLOYMENT_SUMMARY_SHA}" ]] || fail "deployment summary hash mismatch"
[[ "$(tr -d '\r\n' < "${ALLOCATION_JOB_ID_FILE}")" = "${ALLOCATION_JOB_ID}" ]] || fail "allocation-probe job id record mismatch"
[[ "$(sha256sum "${ALLOCATION_STDOUT}" | awk '{print $1}')" = "${ALLOCATION_STDOUT_SHA}" ]] || fail "allocation-probe standard output hash mismatch"
[[ ! -s "${ALLOCATION_STDERR}" ]] || fail "allocation-probe standard error is not empty"
[[ "$(sha256sum "${ALLOCATION_STDERR}" | awk '{print $1}')" = "${EMPTY_SHA}" ]] || fail "allocation-probe standard error hash mismatch"
sacct -j "${ALLOCATION_JOB_ID}" -n -P --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' -v id="${ALLOCATION_JOB_ID}" '$1==id && $2=="tukf09-455-a800-v2-map" && $3=="COMPLETED" && $4=="0:0" {ok=1} END {exit(ok ? 0 : 1)}' || fail "package allocation probe is not completed with exit code 0:0"

source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || \
source "${HOME}/miniconda3/etc/profile.d/conda.sh" || fail "cannot load conda"
conda activate nh_final || fail "cannot activate nh_final"
PYTHON="${CONDA_PREFIX}/bin/python"
if ! "${PYTHON}" -B - "${DEPLOYMENT_SUMMARY}" "${EXECUTION_CONFIG}" "${ALLOCATION_STDOUT}" <<'PY'
import json
from pathlib import Path
import sys

summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
config = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
probe_lines = Path(sys.argv[3]).read_text(encoding="utf-8").splitlines()
assert summary["archive_sha256"] == "e08f7daee8f3b61bab520c044568fbce4ee306cbbbdc2a1d3fa45e95357102f7"
assert summary["bundle_manifest_sha256"] == "9f133931bbd2e840fff74358a12d4be2222e359982751cae389a21be8cf317e8"
assert summary["member_count"] == 2807
assert summary["formal_evaluation_authorized"] is False
assert summary["remote_root"] == "/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2_20260831"
assert summary["status"] == "A800_EXCLUSIVE_V2_DEPLOYED_STRICT_BUNDLE_VERIFIED_FORMAL_EVALUATION_HOLD"
assert config["schema_version"] == "tukf09_455_basin_hpc_execution_a800_exclusive_v2"
assert config["experiment_id"] == "TUKF09_455_BASIN_ZERO_VALIDATION_TARGET_VARIANCE_REVISION_V1"
assert config["status"] == "HPC_TECHNICAL_EXECUTION_FROZEN_FORMAL_EVALUATION_HOLD"
assert config["execution_route"]["formal_evaluation_access"] is False
assert config["execution_route"]["neural_model_parallelism"] == 1
assert config["scientific_identity"]["ordered_basin_count"] == 455
assert config["scientific_identity"]["excluded_basins"] == ["08202700"]
assert config["slurm"]["exclusive_node"] is True
assert config["slurm"]["gpus"] == 1
assert config["forbidden_actions"][-1] == "overwrite_an_existing_remote_experiment_or_staged_data_tree"
assert probe_lines[1:] == ["TUKF09_455_GPU_ALLOCATION_MAPPING_COMPLETED"]
probe = json.loads(probe_lines[0])
assert probe["status"] == "GPU_ALLOCATION_MAPPING_PASS"
assert probe["cuda_available"] is True
assert probe["cuda_device_count"] == 1
assert probe["cuda_device_names"] == ["NVIDIA A800-SXM4-80GB"]
assert probe["exclusive_node_runtime_evidence_passed"] is True
assert probe["slurm_job_id"] == "217143"
assert probe["slurm_job_node_count"] == 1
assert probe["slurm_cpus_on_node"] == 64
assert probe["slurm_job_cpus_per_node_normalized"] == 64
assert probe["slurm_cpus_per_task"] == 4
assert probe["slurm_gpu_allocation_variable_present"] is True
assert probe["slurm_job_gpus"] == "0"
assert probe["selected_global_gpu_id"] == "0"
assert probe["nvidia_selected_gpu_uuid"] == probe["torch_process_gpu_uuid"]
assert probe["nvidia_selected_device"] == probe["torch_process_gpu_uuid"] + ", NVIDIA A800-SXM4-80GB"
PY
then
  fail "frozen deployment, no-evaluation contract, or allocation evidence failed semantic verification"
fi

echo "=== PRISTINE PREPARATION TARGET GATES ==="
for item in \
  "${ROOT}/runtime_v2" \
  "${ROOT}/status/initial_bundle_verification.json" \
  "${ROOT}/status/staged_training_sources.json" \
  "${ROOT}/status/preparation_probe.json" \
  "${ROOT}/status/hpc_technical_admission.json" \
  "${ROOT}/status/preparation.lock" \
  "${JOB_ID_FILE}" \
  "${STAGED_ROOT}" \
  "${RESULTS_ROOT}"; do
  [[ ! -e "${item}" && ! -L "${item}" ]] || fail "preparation target already exists or is linked: ${item}"
done
if compgen -G "${ROOT}/runtime_v2.pending.*" >/dev/null; then
  fail "a pending private runtime already exists"
fi
if compgen -G "${ROOT}/status/staged_training_sources.pending-*" >/dev/null; then
  fail "a pending staged-data tree already exists"
fi
if compgen -G "${ROOT}/logs/prepare-*.out" >/dev/null || compgen -G "${ROOT}/logs/prepare-*.err" >/dev/null; then
  fail "preparation logs already exist"
fi
for name in selection evaluation formal_evaluation; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden post-training output exists: ${name}"
done

echo "=== SAME-NAME JOB GATE ==="
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot inspect current jobs: ${squeue_output}"
same_name=$(printf '%s\n' "${squeue_output}" | awk -F'|' -v name="${JOB_NAME}" '$2==name {print $0}')
[[ -z "${same_name}" ]] || fail "same-name preparation job already exists: ${same_name}"

echo "=== EXACTLY ONE ISOLATED PREPARATION SUBMISSION ==="
submit_output=$(sbatch "${PREPARE_SCRIPT}" 2>&1)
submit_rc=$?
printf '%s\n' "${submit_output}"
job_ids=$(printf '%s\n' "${submit_output}" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
job_id_count=$(printf '%s\n' "${job_ids}" | awk 'NF{count++} END{print count+0}')
[[ "${submit_rc}" -eq 0 && "${job_id_count}" -eq 1 ]] || fail "preparation submission not proven exactly once (wrapper_rc=${submit_rc}, parsed_count=${job_id_count})"
job_id=$(printf '%s\n' "${job_ids}" | awk 'NF{print; exit}')
case "${job_id}" in
  ''|*[!0-9]*) fail "invalid preparation job id" ;;
esac
pending="${JOB_ID_FILE}.pending.$$"
( set -o noclobber; printf '%s\n' "${job_id}" > "${pending}" ) || fail "cannot write pending preparation job id"
ln "${pending}" "${JOB_ID_FILE}" || fail "preparation job id target appeared concurrently"
rm "${pending}" || fail "cannot remove pending preparation job id link"
[[ -f "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" && "$(stat -c '%h' "${JOB_ID_FILE}")" -eq 1 ]] || fail "published preparation job id record is irregular"
[[ "$(tr -d '\r\n' < "${JOB_ID_FILE}")" = "${job_id}" ]] || fail "published preparation job id record differs"

echo "=== IMMEDIATE STATE ==="
echo "PREPARATION_JOB_ID=${job_id}"
squeue -j "${job_id}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true
echo "TUKF09_455_A800_EXCLUSIVE_V2_PREPARATION_SUBMITTED_ONCE"
