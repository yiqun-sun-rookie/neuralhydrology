#!/bin/bash
# Read-only terminal-state and evidence inspection for the one already-submitted
# v2r4 allocation probe. This command submits, cancels, or mutates nothing.
set -euo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r4_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
JOB_ID=217219
JOB_NAME=tukf09-455-v2r4-map
JOB_ID_FILE="${ROOT}/status/allocation_probe_job_id.txt"
SUBMISSION_LOCK="${ROOT}/status/allocation_probe_submission.lock"
STDOUT="${ROOT}/logs/allocation-probe-${JOB_ID}.out"
STDERR="${ROOT}/logs/allocation-probe-${JOB_ID}.err"
MAILBOX_ROOT="$(pwd -P)"
RESULT_49="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_49.txt"
RESULT_49_COMMIT=462c2b88daa0485e4382a6500a8704f895bd84ba
RESULT_49_PARENT=9ee007f501bf353e8c0264207613c49c0a674a37
RESULT_49_SIZE=521
RESULT_49_SHA=aa0c64683a46bc1be7dd3090822b93eaf64167f56eaa4f603fe2f68004c39b26
SUBMISSION_COMMAND_SHA=d41007320058483fe1de5892dd2ccc9f83288e13de335875726824d42ddacc66
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== FROZEN SEQUENCE 49 SUBMISSION EVIDENCE ==="
[[ -x "${PYTHON}" ]] || fail "shared Python launcher missing"
[[ -f "${RESULT_49}" && ! -L "${RESULT_49}" ]] || fail "sequence 49 result is missing, linked, or irregular"
[[ "$(stat -c '%h' "${RESULT_49}")" -eq 1 ]] || fail "sequence 49 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_49}")" -eq "${RESULT_49_SIZE}" ]] || fail "sequence 49 result size changed"
[[ "$(sha256sum "${RESULT_49}" | awk '{print $1}')" = "${RESULT_49_SHA}" ]] || fail "sequence 49 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_49.txt)" = "${RESULT_49_COMMIT}" ]] || fail "sequence 49 result commit changed"
[[ "$(git rev-parse "${RESULT_49_COMMIT}^")" = "${RESULT_49_PARENT}" ]] || fail "sequence 49 result parent changed"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_49_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_49.txt" ]] || fail "sequence 49 result commit surface changed"
[[ "$(git show "${RESULT_49_PARENT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${SUBMISSION_COMMAND_SHA}" ]] || fail "sequence 49 submission command hash changed"

"${PYTHON}" -B - "${RESULT_49}" "${JOB_ID}" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
job_id = sys.argv[2]
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=49"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=1"
assert lines[-1].startswith("### finished=")
assert lines.count(f"Submitted batch job {job_id}") == 1
assert "sync: invalid option -- 'f'" in lines
assert "Try 'sync --help' for more information." in lines
assert "TUKF09_455_A800_EXCLUSIVE_V2R4_ALLOCATION_PROBE_SUBMITTED_ONCE" not in lines
PY

echo "=== FROZEN JOB RECORD ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${ROOT}/logs" "${ROOT}/status" "${SUBMISSION_LOCK}"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing, linked, or irregular: ${item}"
done
[[ -f "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]] || fail "allocation job id record missing, linked, or irregular"
[[ "$(stat -c '%h' "${JOB_ID_FILE}")" -eq 1 ]] || fail "allocation job id record hard-link count changed"
[[ "$(stat -c '%a' "${JOB_ID_FILE}")" = "444" ]] || fail "allocation job id record mode changed"
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
  "${ROOT}/offline_inputs_v2r4" \
  "${ROOT}/runtime_v2r4" \
  "${ROOT}/status/PREPARATION_FAILED.json" \
  "${ROOT}/status/allocation_probe.json" \
  "${ROOT}/status/initial_bundle_verification.json" \
  "${ROOT}/status/staged_training_sources.json" \
  "${ROOT}/status/preparation_probe.json" \
  "${ROOT}/status/hpc_technical_admission.json" \
  "${ROOT}/status/preparation.lock" \
  "${ROOT}/status/preparation_job_id.txt" \
  "${ROOT}/status/training_submission.lock" \
  "${ROOT}/status/training_job_id.txt"; do
  [[ ! -e "${item}" && ! -L "${item}" ]] || fail "downstream output exists before allocation inspection: ${item}"
done
shopt -s nullglob
runtime_pending=("${ROOT}"/runtime_v2r4.pending.*)
shopt -u nullglob
[[ "${#runtime_pending[@]}" -eq 0 ]] || fail "private-runtime pending path exists before allocation inspection"
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
    echo "STDOUT_SIZE=$(stat -c '%s' "${STDOUT}")"
    echo "STDOUT_SHA256=$(sha256sum "${STDOUT}" | awk '{print $1}')"
    echo "STDERR_SIZE=$(stat -c '%s' "${STDERR}")"
    echo "STDERR_SHA256=$(sha256sum "${STDERR}" | awk '{print $1}')"
    sed -n '1,5p' "${STDOUT}"
    "${PYTHON}" -B - "${STDOUT}" "${JOB_ID}" <<'PY'
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
    echo "TUKF09_455_A800_EXCLUSIVE_V2R4_ALLOCATION_PROBE_COMPLETED_VERIFIED"
    ;;
  PENDING|RUNNING|CONFIGURING|COMPLETING)
    echo "TUKF09_455_A800_EXCLUSIVE_V2R4_ALLOCATION_PROBE_NOT_TERMINAL state=${state} exit_code=${exit_code}"
    ;;
  *)
    if [[ -f "${STDOUT}" && ! -L "${STDOUT}" ]]; then
      echo "STDOUT_SIZE=$(stat -c '%s' "${STDOUT}")"
      echo "STDOUT_SHA256=$(sha256sum "${STDOUT}" | awk '{print $1}')"
      sed -n '1,80p' "${STDOUT}"
    fi
    if [[ -f "${STDERR}" && ! -L "${STDERR}" ]]; then
      echo "STDERR_SIZE=$(stat -c '%s' "${STDERR}")"
      echo "STDERR_SHA256=$(sha256sum "${STDERR}" | awk '{print $1}')"
      sed -n '1,80p' "${STDERR}"
    fi
    echo "TUKF09_455_A800_EXCLUSIVE_V2R4_ALLOCATION_PROBE_TERMINAL_NONPASS state=${state} exit_code=${exit_code}"
    ;;
esac
