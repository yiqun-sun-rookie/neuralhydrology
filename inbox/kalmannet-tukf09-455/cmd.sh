#!/bin/bash
# Read-only terminal-state and evidence inspection for the one already-submitted
# v2r5 allocation probe. This command submits, cancels, or mutates nothing.
set -euo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
JOB_ID=217678
JOB_NAME=tukf09-455-v2r5-map
JOB_ID_FILE="${ROOT}/status/allocation_probe_job_id.txt"
SUBMISSION_LOCK="${ROOT}/status/allocation_probe_submission.lock"
STDOUT="${ROOT}/logs/allocation-probe-${JOB_ID}.out"
STDERR="${ROOT}/logs/allocation-probe-${JOB_ID}.err"
MAILBOX_ROOT="$(pwd -P)"
RESULT_63="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_63.txt"
RESULT_63_COMMIT=35c5282377545aae37a440534bf1f57115368608
RESULT_63_COMMAND_COMMIT=de08f2ec437f470a2b2bfac4e7c46fbbc9ec6b14
RESULT_63_COMMAND_SHA=1695e85f435dc8616d2631602c1f8b231189ec48b9c86df51061884ba0514912
RESULT_63_SIZE=918
RESULT_63_SHA=33b8bbe9c51fcb4377992e8d8bdc6e4e3d799d16c721b6e7d44baaf53cda56d8
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== FROZEN SEQUENCE 63 SUBMISSION EVIDENCE ==="
[[ -x "${PYTHON}" ]] || fail "shared Python launcher missing"
[[ -f "${RESULT_63}" && ! -L "${RESULT_63}" ]] || fail "sequence 63 result missing or linked"
[[ "$(stat -c '%h' "${RESULT_63}")" -eq 1 ]] || fail "sequence 63 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_63}")" -eq "${RESULT_63_SIZE}" ]] || fail "sequence 63 result size changed"
[[ "$(sha256sum "${RESULT_63}" | awk '{print $1}')" = "${RESULT_63_SHA}" ]] || fail "sequence 63 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_63.txt)" = "${RESULT_63_COMMIT}" ]] || fail "sequence 63 result commit changed"
git merge-base --is-ancestor "${RESULT_63_COMMAND_COMMIT}" "${RESULT_63_COMMIT}" || fail "sequence 63 command is not an ancestor of its result"
[[ "$(git log -1 --format=%H "${RESULT_63_COMMIT}^" -- inbox/kalmannet-tukf09-455/cmd.sh)" = "${RESULT_63_COMMAND_COMMIT}" ]] || fail "sequence 63 command was not the last channel command before its result"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_63_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_63.txt" ]] || fail "sequence 63 result commit surface changed"
[[ "$(git show "${RESULT_63_COMMAND_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${RESULT_63_COMMAND_SHA}" ]] || fail "sequence 63 command hash changed"

"${PYTHON}" -B - "${RESULT_63}" "${JOB_ID}" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
job_id = sys.argv[2]
assert len(lines) == 19
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=63"
assert lines[1] == "### host=login4"
assert lines[2].startswith("### started=")
assert lines[3] == "### ---------- output ----------"
assert lines[4:10] == [
    "=== FROZEN SEQUENCE 61 DEPLOYMENT EVIDENCE ===",
    "=== FROZEN SEQUENCE 62 PRE-SUBMISSION FAILURE EVIDENCE ===",
    "=== IMMUTABLE DEPLOYMENT AND CONTRACT GATES ===",
    "=== SAME-NAME JOB GATE ===",
    "=== EXCLUSIVE ALLOCATION SUBMISSION LOCK ===",
    "=== EXACTLY ONE PACKAGE ALLOCATION PROBE SUBMISSION ===",
]
assert lines[10] == f"Submitted batch job {job_id}"
assert lines[11] == "=== IMMEDIATE STATE ==="
assert lines[12] == f"ALLOCATION_PROBE_JOB_ID={job_id}"
assert lines[13].startswith("             JOBID")
assert job_id in lines[14]
assert "tukf09-455-v2r5-map" in lines[14]
assert lines[15] == "TUKF09_455_A800_EXCLUSIVE_V2R5_ALLOCATION_PROBE_SUBMITTED_ONCE_FORMAL_EVALUATION_HOLD"
assert lines[16] == "### ---------- end ----------"
assert lines[17] == "### exit_code=0"
assert lines[18].startswith("### finished=")
assert lines.count(f"Submitted batch job {job_id}") == 1
assert not any(line.startswith("FATAL:") for line in lines)
PY

echo "=== FROZEN JOB RECORD ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${ROOT}/logs" "${ROOT}/status" "${SUBMISSION_LOCK}"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing or linked: ${item}"
done
[[ -f "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]] || fail "allocation job id record missing or linked"
[[ "$(stat -c '%h' "${JOB_ID_FILE}")" -eq 1 ]] || fail "allocation job id record hard-link count changed"
[[ "$(stat -c '%a' "${JOB_ID_FILE}")" = "444" ]] || fail "allocation job id record mode changed"
"${PYTHON}" -B - "${JOB_ID_FILE}" "${JOB_ID}" <<'PY'
from pathlib import Path
import sys

assert Path(sys.argv[1]).read_bytes() == (sys.argv[2] + "\n").encode("ascii")
PY

echo "=== SLURM STATE ==="
sacct_output=$(sacct -j "${JOB_ID}" -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,NodeList,Elapsed,Start,End 2>&1) || fail "sacct failed: ${sacct_output}"
printf '%s\n' "${sacct_output}"
job_row=$(printf '%s\n' "${sacct_output}" | awk -F'|' -v id="${JOB_ID}" '$1==id {print; found=1} END {exit(found ? 0 : 1)}') || fail "exact allocation job row missing"
state=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $4}')
exit_code=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $5}')
recorded_name=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $2}')
recorded_partition=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $3}')
[[ "${recorded_name}" = "${JOB_NAME}" ]] || fail "allocation job name mismatch"
[[ "${recorded_partition}" = "hgpu8" ]] || fail "allocation partition mismatch"
squeue -j "${JOB_ID}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true

echo "=== ZERO-DOWNSTREAM-OUTPUT GATE ==="
for item in \
  "${ROOT}/offline_inputs_v2r5" \
  "${ROOT}/runtime_v2r5" \
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
runtime_pending=("${ROOT}"/runtime_v2r5.pending.*)
shopt -u nullglob
[[ "${#runtime_pending[@]}" -eq 0 ]] || fail "private-runtime pending path exists before allocation inspection"
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output exists: ${name}"
done

case "${state}" in
  COMPLETED)
    [[ "${exit_code}" = "0:0" ]] || fail "completed allocation job has nonzero exit code: ${exit_code}"
    for item in "${STDOUT}" "${STDERR}"; do
      [[ -f "${item}" && ! -L "${item}" ]] || fail "terminal allocation log missing or linked: ${item}"
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
    echo "TUKF09_455_A800_EXCLUSIVE_V2R5_ALLOCATION_PROBE_COMPLETED_VERIFIED_FORMAL_EVALUATION_HOLD"
    ;;
  PENDING|RUNNING|CONFIGURING|COMPLETING)
    echo "TUKF09_455_A800_EXCLUSIVE_V2R5_ALLOCATION_PROBE_NOT_TERMINAL state=${state} exit_code=${exit_code} FORMAL_EVALUATION_HOLD"
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
    echo "TUKF09_455_A800_EXCLUSIVE_V2R5_ALLOCATION_PROBE_TERMINAL_NONPASS state=${state} exit_code=${exit_code} FORMAL_EVALUATION_HOLD"
    ;;
esac
