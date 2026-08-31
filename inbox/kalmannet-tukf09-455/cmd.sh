#!/bin/bash
# Read-only state and, if terminal, strict evidence audit for v2r3 preparation job 217185.
set -eo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r3_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
STAGED_ROOT="${PROJECT_ROOT}/G:/github/pycharm/projects/neuralhydrology/data/camels_us"
RUNTIME_ROOT="${ROOT}/runtime_v2r3"
PRIVATE_MANIFEST="${RUNTIME_ROOT}/evidence/private_runtime_manifest.json"
INITIAL_BUNDLE="${ROOT}/status/initial_bundle_verification.json"
STAGED_MANIFEST="${ROOT}/status/staged_training_sources.json"
PREPARATION_PROBE="${ROOT}/status/preparation_probe.json"
FILTER_SEAL="${RESULTS_ROOT}/control/filter_rebinding/independent/manifest.final.sha256.json"
JOB_ID=217185
JOB_NAME=tukf09-455-v2r3-prepare
JOB_ID_FILE="${ROOT}/status/preparation_job_id.txt"
SUBMISSION_LOCK="${ROOT}/status/preparation_submission.lock"
STDOUT="${ROOT}/logs/prepare-${JOB_ID}.out"
STDERR="${ROOT}/logs/prepare-${JOB_ID}.err"
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="${PROJECT_ROOT}"

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== FROZEN PREPARATION SUBMISSION EVIDENCE ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${ROOT}/logs" "${ROOT}/status" "${SUBMISSION_LOCK}"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing, linked, or irregular: ${item}"
done
[[ -f "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]] || fail "preparation job id record missing, linked, or irregular"
[[ "$(stat -c '%h' "${JOB_ID_FILE}")" -eq 1 ]] || fail "preparation job id record hard-link count changed"
[[ "$(tr -d '\r\n' < "${JOB_ID_FILE}")" = "${JOB_ID}" ]] || fail "preparation job id record mismatch"

echo "=== SLURM STATE ==="
sacct_output=$(sacct -j "${JOB_ID}" -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,NodeList,Elapsed,Start,End 2>&1) || fail "sacct failed: ${sacct_output}"
printf '%s\n' "${sacct_output}"
job_row=$(printf '%s\n' "${sacct_output}" | awk -F'|' -v id="${JOB_ID}" '$1==id {print; found=1} END {exit(found ? 0 : 1)}') || fail "exact preparation job row missing"
state=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $4}')
exit_code=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $5}')
recorded_name=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $2}')
[[ "${recorded_name}" = "${JOB_NAME}" ]] || fail "preparation job name mismatch"
squeue -j "${JOB_ID}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true

echo "=== FORMAL EVALUATION HOLD ==="
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output exists: ${name}"
done
for item in "${ROOT}/status/hpc_technical_admission.json" "${ROOT}/status/training_submission.lock" "${ROOT}/status/training_job_id.txt"; do
  [[ ! -e "${item}" && ! -L "${item}" ]] || fail "downstream technical admission or training evidence exists prematurely: ${item}"
done

case "${state}" in
  PENDING|RUNNING|CONFIGURING|COMPLETING)
    echo "TUKF09_455_A800_EXCLUSIVE_V2R3_PREPARATION_NOT_TERMINAL state=${state} exit_code=${exit_code}"
    exit 0
    ;;
  COMPLETED)
    [[ "${exit_code}" = "0:0" ]] || fail "completed preparation job has nonzero exit code: ${exit_code}"
    ;;
  *)
    echo "=== PRESERVED TERMINAL NONPASS EVIDENCE ==="
    for log in "${STDOUT}" "${STDERR}"; do
      if [[ -f "${log}" && ! -L "${log}" ]]; then
        echo "LOG=${log} SIZE=$(stat -c '%s' "${log}") SHA256=$(sha256sum "${log}" | awk '{print $1}')"
        tail -c 20000 "${log}"
      fi
    done
    for item in "${ROOT}/runtime_v2r3.pending.${JOB_ID}" "${RUNTIME_ROOT}" "${INITIAL_BUNDLE}" "${STAGED_MANIFEST}" "${PREPARATION_PROBE}" "${STAGED_ROOT}" "${FILTER_SEAL}"; do
      if [[ -e "${item}" || -L "${item}" ]]; then
        stat -c 'PRESERVED=%F|%s|%h|%n' "${item}" || true
      fi
    done
    echo "TUKF09_455_A800_EXCLUSIVE_V2R3_PREPARATION_TERMINAL_NONPASS state=${state} exit_code=${exit_code}"
    exit 0
    ;;
esac

echo "=== TERMINAL LOG EVIDENCE ==="
for item in "${STDOUT}" "${STDERR}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "terminal preparation log missing, linked, or irregular: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "terminal preparation log hard-link count changed: ${item}"
done
[[ ! -s "${STDERR}" ]] || fail "preparation Slurm standard error is not empty"
[[ "$(tail -n 1 "${STDOUT}")" = "TUKF09_455_HPC_PREPARATION_PROBE_COMPLETED" ]] || fail "preparation completion marker missing"
echo "STDOUT_SIZE=$(stat -c '%s' "${STDOUT}")"
echo "STDOUT_SHA256=$(sha256sum "${STDOUT}" | awk '{print $1}')"
echo "STDERR_SHA256=$(sha256sum "${STDERR}" | awk '{print $1}')"
echo "STDOUT_LAST_LINE=$(tail -n 1 "${STDOUT}")"

echo "=== STRICT PREPARATION ARTIFACT GATES ==="
for item in "${RUNTIME_ROOT}" "${RUNTIME_ROOT}/pysite" "${RUNTIME_ROOT}/wheelhouse" "${STAGED_ROOT}"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "prepared directory missing, linked, or irregular: ${item}"
done
for item in "${PRIVATE_MANIFEST}" "${INITIAL_BUNDLE}" "${STAGED_MANIFEST}" "${PREPARATION_PROBE}" "${FILTER_SEAL}" "${ROOT}/status/preparation.lock"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "prepared evidence missing, linked, or irregular: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "prepared evidence hard-link count changed: ${item}"
done
[[ ! -e "${ROOT}/runtime_v2r3.pending.${JOB_ID}" && ! -L "${ROOT}/runtime_v2r3.pending.${JOB_ID}" ]] || fail "runtime pending directory remains after successful job"
if compgen -G "${ROOT}/status/staged_training_sources.pending-*" >/dev/null; then
  fail "staged-data pending directory remains after successful job"
fi

if ! "${PYTHON}" -B - "${PROJECT_ROOT}" "${ROOT}" "${JOB_ID}" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys

project = Path(sys.argv[1])
root = Path(sys.argv[2])
job_id = sys.argv[3]
stage_path = project / "hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/stage_and_train.py"
spec = importlib.util.spec_from_file_location("tukf09_stage_v2r3_audit", stage_path)
assert spec is not None and spec.loader is not None
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)

runtime = root / "runtime_v2r3"
private_path = runtime / "evidence/private_runtime_manifest.json"
initial_path = root / "status/initial_bundle_verification.json"
staged_path = root / "status/staged_training_sources.json"
probe_path = root / "status/preparation_probe.json"
filter_seal = project / "results/tukf09_455_basin_zero_validation_target_variance_revision_v1/control/filter_rebinding/independent/manifest.final.sha256.json"

private = stage.verify_private_runtime_manifest(
    manifest_path=private_path,
    pysite=runtime / "pysite",
    wheelhouse=runtime / "wheelhouse",
    import_check=False,
)
initial = stage.read_json(initial_path, root=root, canonical=True)
staged = stage.read_json(staged_path, root=root, canonical=True)
probe = stage.read_json(probe_path, root=root, canonical=True)
stage._verify_payload_identity(initial, label="initial bundle verification")
stage._verify_payload_identity(staged, label="staged training sources")
stage._verify_payload_identity(probe, label="preparation probe")

assert initial["status"] == "STRICT_PRISTINE_A800_EXCLUSIVE_V2R3_BUNDLE_VERIFIED_BEFORE_RUNTIME_MUTATION"
assert initial["member_count"] == 2808
assert initial["admitted_executable_count"] == 30
assert initial["admitted_test_count"] == 12
assert initial["formal_evaluation_output_count"] == 0
assert initial["mutable_file_count_at_verification"] == 0
assert initial["mutable_directory_count_at_verification"] == 0
assert initial["scientific_contract_changed"] is False

assert staged["status"] == "STAGED_455_TRAINING_VALIDATION_SOURCE_FILES_EVALUATION_HOLD"
assert len(staged["ordered_basin_ids"]) == 455
assert len(staged["file_sha256"]) == 911
assert len(staged["file_size"]) == 911
assert staged["file_count"] == 911
assert staged["evaluation_array_reads"] == 0
records = {
    name: {"sha256": staged["file_sha256"][name], "size_bytes": staged["file_size"][name]}
    for name in staged["file_sha256"]
}
verified_stage = stage.verify_staged_training_sources(
    destination_root=project / "G:/github/pycharm/projects/neuralhydrology/data/camels_us",
    records=records,
)
assert verified_stage["file_count"] == 911
assert verified_stage["total_size_bytes"] == staged["total_size_bytes"]

assert private["status"] == "PRIVATE_RUNTIME_FROZEN_NOT_A_SCIENTIFIC_CONTRACT_CHANGE"
assert private["target_versions"] == {"numpy": "1.26.4", "psutil": "5.9.0", "torch": "2.2.2"}
assert private["private_dependency_closure_complete"] is True
assert private["shared_nh_final_modified"] is False
assert private["offline_input_manifest_sha256"] == "0e9cbcec8ad25db938ceed10460357c248e8f9e59a681cd9c84fef8387fbb339"
assert private["offline_input_identity_sha256"] == "c354a618962b3d2462a34459396f58d89686adc2fa18281db7d90ce0d9d3a137"
assert private["offline_input_total_file_count"] == 24
assert private["offline_input_total_bytes"] == 2817756909

assert probe["status"] == "HPC_A800_EXCLUSIVE_V2R3_PREPARED_FILTERS_455_NEURAL_0_OF_9_EVALUATION_HOLD"
assert probe["filter_unit_count"] == 455
assert probe["neural_model_unit_count"] == 0
assert probe["evaluation_array_reads"] == 0
assert probe["evaluation_predictions"] == 0
assert probe["evaluation_metrics"] == 0
assert probe["evaluation_outputs"] == 0
assert probe["scientific_contract_changed"] is False
assert probe["bundle_manifest_sha256"] == "b64829885d5330feb2c66cc7558b1ea3ea38b1def4ae889566480cb369381f6b"
assert probe["initial_bundle_verification_sha256"] == stage.sha256_file(initial_path)
assert probe["initial_bundle_verification_identity_sha256"] == initial["identity_sha256"]
assert probe["private_runtime_manifest_sha256"] == stage.sha256_file(private_path)
assert probe["private_runtime_identity_sha256"] == private["identity_sha256"]
assert probe["staged_sources_manifest_sha256"] == stage.sha256_file(staged_path)
assert probe["staged_sources_identity_sha256"] == staged["identity_sha256"]
assert probe["remote_filter_installation_final_sha256"] == stage.sha256_file(filter_seal)
runtime_identity = probe["runtime"]
assert runtime_identity["slurm_job_id"] == job_id
assert runtime_identity["cuda_available"] is True
assert runtime_identity["cuda_device_count"] == 1
assert runtime_identity["cuda_device_name"] == "NVIDIA A800-SXM4-80GB"
assert runtime_identity["cuda_compute_capability"] == [8, 0]
assert runtime_identity["torch_base_version"] == "2.2.2"
assert runtime_identity["numpy_version"] == "1.26.4"
assert runtime_identity["psutil_version"] == "5.9.0"
assert runtime_identity["exclusive_node_runtime_evidence_passed"] is True
assert runtime_identity["slurm_job_node_count"] == 1
assert runtime_identity["slurm_cpus_on_node"] == 64
assert runtime_identity["slurm_cpus_per_task"] == 4
assert runtime_identity["slurm_gpu_allocation_variable_present"] is True
assert runtime_identity["nvidia_gpu_uuid"] == runtime_identity["torch_process_gpu_uuid"]

print(json.dumps({
    "filter_unit_count": probe["filter_unit_count"],
    "initial_bundle_sha256": stage.sha256_file(initial_path),
    "preparation_probe_identity_sha256": probe["identity_sha256"],
    "preparation_probe_sha256": stage.sha256_file(probe_path),
    "private_runtime_identity_sha256": private["identity_sha256"],
    "private_runtime_manifest_sha256": stage.sha256_file(private_path),
    "remote_filter_seal_sha256": stage.sha256_file(filter_seal),
    "staged_file_count": staged["file_count"],
    "staged_sources_identity_sha256": staged["identity_sha256"],
    "staged_sources_manifest_sha256": stage.sha256_file(staged_path),
}, sort_keys=True))
PY
then
  fail "completed preparation artifacts failed strict semantic verification"
fi

echo "TUKF09_455_A800_EXCLUSIVE_V2R3_PREPARATION_COMPLETED_STRICTLY_VERIFIED_ADMISSION_NOT_CREATED"
