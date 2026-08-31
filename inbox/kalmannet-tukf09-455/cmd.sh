#!/bin/bash
# Submit exactly one isolated v2r1 A800 preparation job after its package allocation probe passed.
set -o pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r1_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
SOURCE_ROOT=/data1/home/sunyiq/neuralhydrology/data/camels_us
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
STAGED_ROOT="${PROJECT_ROOT}/G:/github/pycharm/projects/neuralhydrology/data/camels_us"
PREPARE_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r1/probe_gpu.slurm"
PREPARE_SCRIPT_SHA=c46b65d3f7200284d3fad1896570a8c0ea3c86d17538530261a87b0acafad350
STAGE_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r1/stage_and_train.py"
STAGE_SCRIPT_SHA=15d0f92a7360d48c804853436475ec9a0d83fb356be2536aa0fd816b9c741621
ALLOCATION_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r1/allocation_probe.slurm"
ALLOCATION_SCRIPT_SHA=5dc332b67998b6a2fa3b5a37f3db40694ff21cea832ff61750a527f136a4597b
EXECUTION_CONFIG="${PROJECT_ROOT}/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r1.json"
EXECUTION_CONFIG_SHA=35a0de2a9f04faf51351fbd6f928575b0c293dd5d90c05ddfab9e3a05995d33b
DEPLOYMENT_SUMMARY="${ROOT}/status/deployment_summary.json"
DEPLOYMENT_SUMMARY_SHA=23265560f78d87b0f12ecea7e637d8f7e2d6be3ca86bfa7428c9de9af1e12ab0
ALLOCATION_JOB_ID=217162
ALLOCATION_JOB_ID_FILE="${ROOT}/status/allocation_probe_job_id.txt"
ALLOCATION_STDOUT="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.out"
ALLOCATION_STDOUT_SHA=8004a5be9c9f31b664fb15c387dd22cf9dc68dc79d1ec12c31ae398a1af55e5c
ALLOCATION_STDERR="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.err"
EMPTY_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
JOB_NAME=tukf09-455-v2r1-prepare
JOB_ID_FILE="${ROOT}/status/preparation_job_id.txt"
SUBMISSION_LOCK="${ROOT}/status/preparation_submission.lock"

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
  awk -F'|' -v id="${ALLOCATION_JOB_ID}" '$1==id && $2=="tukf09-455-v2r1-map" && $3=="COMPLETED" && $4=="0:0" {ok=1} END {exit(ok ? 0 : 1)}' || fail "package allocation probe is not completed with exit code 0:0"

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
assert summary["archive_sha256"] == "d15ec97d9297cee003314a5697269b4cab8e55a91a78d7fda628729edd7146ea"
assert summary["bundle_manifest_sha256"] == "ca7bc5b7bdd9a451d691130c6881cd146c3d89d2ef01385237faac0f91c46ad4"
assert summary["failed_predecessor_job_id"] == 217149
assert summary["failed_predecessor_root"] == "/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2_20260831"
assert summary["member_count"] == 2807
assert summary["formal_evaluation_authorized"] is False
assert summary["remote_root"] == "/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r1_20260901"
assert summary["status"] == "A800_EXCLUSIVE_V2R1_DEPLOYED_STRICT_BUNDLE_VERIFIED_FORMAL_EVALUATION_HOLD"
assert config["schema_version"] == "tukf09_455_basin_hpc_execution_a800_exclusive_v2r1"
assert config["experiment_id"] == "TUKF09_455_BASIN_ZERO_VALIDATION_TARGET_VARIANCE_REVISION_V1"
assert config["status"] == "HPC_TECHNICAL_EXECUTION_FROZEN_FORMAL_EVALUATION_HOLD"
assert config["technical_retry"]["revision"] == "v2r1"
assert config["technical_retry"]["failed_preparation_job_id"] == 217149
assert config["technical_retry"]["scientific_contract_changed"] is False
assert config["technical_retry"]["formal_evaluation_authorized"] is False
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
assert probe["slurm_job_id"] == "217162"
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
  "${ROOT}/runtime_v2r1" \
  "${ROOT}/status/initial_bundle_verification.json" \
  "${ROOT}/status/staged_training_sources.json" \
  "${ROOT}/status/preparation_probe.json" \
  "${ROOT}/status/hpc_technical_admission.json" \
  "${ROOT}/status/preparation.lock" \
  "${SUBMISSION_LOCK}" \
  "${JOB_ID_FILE}" \
  "${STAGED_ROOT}" \
  "${RESULTS_ROOT}"; do
  [[ ! -e "${item}" && ! -L "${item}" ]] || fail "preparation target already exists or is linked: ${item}"
done
if compgen -G "${ROOT}/runtime_v2r1.pending.*" >/dev/null; then
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

echo "=== ATOMIC PREPARATION SUBMISSION LOCK ==="
mkdir "${SUBMISSION_LOCK}" || fail "cannot acquire the preparation submission lock"
[[ -d "${SUBMISSION_LOCK}" && ! -L "${SUBMISSION_LOCK}" ]] || fail "preparation submission lock is linked or irregular"
[[ ! -e "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]] || fail "preparation job id record appeared after lock acquisition"
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot recheck current jobs after lock acquisition: ${squeue_output}"
same_name=$(printf '%s\n' "${squeue_output}" | awk -F'|' -v name="${JOB_NAME}" '$2==name {print $0}')
[[ -z "${same_name}" ]] || fail "same-name preparation job appeared after lock acquisition: ${same_name}"

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
echo "TUKF09_455_A800_EXCLUSIVE_V2R1_PREPARATION_SUBMITTED_ONCE"
