#!/bin/bash
# Read-only terminal-state and evidence inspection for the one v2r3 allocation probe.
set -eo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r3_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
JOB_ID=217180
JOB_NAME=tukf09-455-v2r3-map
JOB_ID_FILE="${ROOT}/status/allocation_probe_job_id.txt"
SUBMISSION_LOCK="${ROOT}/status/allocation_probe_submission.lock"
STDOUT="${ROOT}/logs/allocation-probe-${JOB_ID}.out"
STDERR="${ROOT}/logs/allocation-probe-${JOB_ID}.err"
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== FROZEN SUBMISSION EVIDENCE ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${ROOT}/logs" "${ROOT}/status" "${SUBMISSION_LOCK}"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing, linked, or irregular: ${item}"
done
[[ -f "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]] || fail "allocation job id record missing, linked, or irregular"
[[ "$(stat -c '%h' "${JOB_ID_FILE}")" -eq 1 ]] || fail "allocation job id record hard-link count changed"
[[ "$(tr -d '\r\n' < "${JOB_ID_FILE}")" = "${JOB_ID}" ]] || fail "allocation job id record mismatch"

echo "=== SLURM STATE ==="
sacct_output=$(sacct -j "${JOB_ID}" -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,NodeList,Elapsed,Start,End 2>&1) || fail "sacct failed: ${sacct_output}"
printf '%s\n' "${sacct_output}"
job_row=$(printf '%s\n' "${sacct_output}" | awk -F'|' -v id="${JOB_ID}" '$1==id {print; found=1} END {exit(found ? 0 : 1)}') || fail "exact allocation job row missing"
state=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $4}')
exit_code=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $5}')
recorded_name=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $2}')
[[ "${recorded_name}" = "${JOB_NAME}" ]] || fail "allocation job name mismatch"
squeue -j "${JOB_ID}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true

echo "=== ZERO-DOWNSTREAM-OUTPUT GATE ==="
for item in \
  "${ROOT}/offline_inputs_v2r3" \
  "${ROOT}/runtime_v2r3" \
  "${ROOT}/status/initial_bundle_verification.json" \
  "${ROOT}/status/staged_training_sources.json" \
  "${ROOT}/status/preparation_probe.json" \
  "${ROOT}/status/hpc_technical_admission.json" \
  "${ROOT}/status/preparation.lock" \
  "${ROOT}/status/preparation_job_id.txt" \
  "${ROOT}/status/training_submission.lock" \
  "${ROOT}/status/training_job_id.txt"; do
  [[ ! -e "${item}" && ! -L "${item}" ]] || fail "downstream output exists before allocation completion: ${item}"
done
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output exists: ${name}"
done

case "${state}" in
  COMPLETED)
    [[ "${exit_code}" = "0:0" ]] || fail "completed allocation job has nonzero exit code: ${exit_code}"
    for item in "${STDOUT}" "${STDERR}"; do
      [[ -f "${item}" && ! -L "${item}" ]] || fail "terminal allocation log missing, linked, or irregular: ${item}"
      [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "terminal allocation log hard-link count changed: ${item}"
    done
    [[ ! -s "${STDERR}" ]] || fail "allocation standard error is not empty"
    echo "STDOUT_SHA256=$(sha256sum "${STDOUT}" | awk '{print $1}')"
    echo "STDERR_SHA256=$(sha256sum "${STDERR}" | awk '{print $1}')"
    sed -n '1,5p' "${STDOUT}"
    if ! "${PYTHON}" -B - "${STDOUT}" "${JOB_ID}" <<'PY'
import json
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
assert len(lines) == 2
record = json.loads(lines[0])
assert lines[1] == "TUKF09_455_GPU_ALLOCATION_MAPPING_COMPLETED"
assert record["status"] == "GPU_ALLOCATION_MAPPING_PASS"
assert record["cuda_available"] is True
assert record["cuda_device_count"] == 1
assert record["cuda_device_names"] == ["NVIDIA A800-SXM4-80GB"]
assert record["exclusive_node_runtime_evidence_passed"] is True
assert record["slurm_job_id"] == sys.argv[2]
assert record["slurm_job_node_count"] == 1
assert record["slurm_cpus_on_node"] == 64
assert record["slurm_job_cpus_per_node_normalized"] == 64
assert record["slurm_cpus_per_task"] == 4
assert record["slurm_gpu_allocation_variable_present"] is True
assert record["nvidia_selected_gpu_uuid"] == record["torch_process_gpu_uuid"]
assert record["nvidia_selected_device"] == record["torch_process_gpu_uuid"] + ", NVIDIA A800-SXM4-80GB"
PY
    then
      fail "allocation standard output failed semantic verification"
    fi
    echo "TUKF09_455_A800_EXCLUSIVE_V2R3_ALLOCATION_PROBE_COMPLETED_VERIFIED"
    ;;
  PENDING|RUNNING|CONFIGURING|COMPLETING)
    echo "TUKF09_455_A800_EXCLUSIVE_V2R3_ALLOCATION_PROBE_NOT_TERMINAL state=${state} exit_code=${exit_code}"
    ;;
  *)
    if [[ -f "${STDOUT}" && ! -L "${STDOUT}" ]]; then
      echo "STDOUT_SHA256=$(sha256sum "${STDOUT}" | awk '{print $1}')"
      sed -n '1,80p' "${STDOUT}"
    fi
    if [[ -f "${STDERR}" && ! -L "${STDERR}" ]]; then
      echo "STDERR_SHA256=$(sha256sum "${STDERR}" | awk '{print $1}')"
      sed -n '1,80p' "${STDERR}"
    fi
    echo "TUKF09_455_A800_EXCLUSIVE_V2R3_ALLOCATION_PROBE_TERMINAL_NONPASS state=${state} exit_code=${exit_code}"
    ;;
esac
