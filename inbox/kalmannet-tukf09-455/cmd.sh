#!/bin/bash
# Read-only monitor for the one admitted v2r4 neural-training job. This
# command submits, cancels, signals, or mutates nothing.
set -euo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r4_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
ADMISSION="${ROOT}/status/hpc_technical_admission.json"
ADMISSION_SHA=b485c75a86e3f39b616b9dc0292696ba24c275038a520177759c27b1c4522930
TRAINING_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/submit_training_gpu.slurm"
TRAINING_SCRIPT_SHA=27283ab2b4a543ce2cce464afd0a9ad86536d0ed5948eba6ba1b313147ac8fba
TRAINING_JOB_ID=217409
TRAINING_JOB_NAME=tukf09-455-v2r4-neural
TRAINING_JOB_ID_FILE="${ROOT}/status/training_job_id.txt"
TRAINING_SUBMISSION_LOCK="${ROOT}/status/training_submission.lock"
TRAINING_STDOUT="${ROOT}/logs/training-${TRAINING_JOB_ID}.out"
TRAINING_STDERR="${ROOT}/logs/training-${TRAINING_JOB_ID}.err"
TRAINING_VERIFICATION="${ROOT}/status/training_verification.${TRAINING_JOB_ID}.json"
BUILDER="${PROJECT_ROOT}/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2r4.py"
BUILDER_SHA=4ccb9026a4de33f71ae173ef7d64d4839e634529219da2c65cff8fcf045215fd
EXECUTION_CONFIG="${PROJECT_ROOT}/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r4.json"
FILTER_SEAL="${RESULTS_ROOT}/control/filter_rebinding/independent/manifest.final.sha256.json"
MAILBOX_ROOT="$(pwd -P)"
RESULT_58="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_58.txt"
RESULT_58_COMMIT=94a28752d54783e6fa13fb3272686d39d3021168
RESULT_58_SIZE=9281
RESULT_58_SHA=4618025f1ae9f204a596db0dd8371f2cf80c2b4c31a5e04e2234536451fca8e6
SUBMISSION_58_COMMIT=c6313e052571e86a63a27ac6d84c9e7d01949fa6
SUBMISSION_58_COMMAND_SHA=5ff24f63285b93beb9064b20d151aee477b7a2c90aa7e117be6233845bd9ab3b
RESULT_59="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_59.txt"
RESULT_59_COMMIT=135c8d001fb0692fb17c73a4acee508b2f59f7ad
RESULT_59_SIZE=2760
RESULT_59_SHA=c5ca5316a269764461d3be82e0d44a76ab261a9a33c264dcf9ca85c262454c93
MONITOR_59_COMMIT=fc7b79d6b7c3b9e903c6b0eab08bb48d7ea31a6d
MONITOR_59_COMMAND_SHA=b26578680b45e3bb90b0fae4bb9b473e20e853fe92dc5f4d18d65e94d01d9d97
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
export PYTHONNOUSERSITE=1
export PYTHONDWRITEBYTECODE=1

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== FROZEN SEQUENCE 58 SINGLE-SUBMISSION EVIDENCE ==="
[[ -x "${PYTHON}" ]] || fail "shared Python launcher missing"
[[ -f "${RESULT_58}" && ! -L "${RESULT_58}" ]] || fail "sequence 58 result is missing, linked, or irregular"
[[ "$(stat -c '%h' "${RESULT_58}")" -eq 1 ]] || fail "sequence 58 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_58}")" -eq "${RESULT_58_SIZE}" ]] || fail "sequence 58 result size changed"
[[ "$(sha256sum "${RESULT_58}" | awk '{print $1}')" = "${RESULT_58_SHA}" ]] || fail "sequence 58 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_58.txt)" = "${RESULT_58_COMMIT}" ]] || fail "sequence 58 result commit changed"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_58_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_58.txt" ]] || fail "sequence 58 result commit surface changed"
git merge-base --is-ancestor "${SUBMISSION_58_COMMIT}" "${RESULT_58_COMMIT}" || fail "sequence 58 command is not an ancestor of its result"
[[ "$(git log -1 --format=%H "${RESULT_58_COMMIT}^" -- inbox/kalmannet-tukf09-455/cmd.sh)" = "${SUBMISSION_58_COMMIT}" ]] || fail "sequence 58 command lineage changed"
[[ "$(git show "${SUBMISSION_58_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${SUBMISSION_58_COMMAND_SHA}" ]] || fail "sequence 58 submission command hash changed"

"${PYTHON}" -B - "${RESULT_58}" "${TRAINING_JOB_ID}" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
job_id = sys.argv[2]
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=58"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=0"
assert lines[-1].startswith("### finished=")
assert lines.count(f"Submitted batch job {job_id}") == 1
assert f"TRAINING_JOB_ID={job_id}" in lines
assert "TUKF09_455_A800_EXCLUSIVE_V2R4_NEURAL_TRAINING_SUBMITTED_ONCE_FORMAL_EVALUATION_HOLD" in lines
assert any(job_id in line and "tukf09-455-v2r4-neural" in line and "PENDING" in line for line in lines)
PY

echo "=== FROZEN SEQUENCE 59 TERMINAL EVIDENCE ==="
[[ -f "${RESULT_59}" && ! -L "${RESULT_59}" ]] || fail "sequence 59 result is missing, linked, or irregular"
[[ "$(stat -c '%h' "${RESULT_59}")" -eq 1 ]] || fail "sequence 59 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_59}")" -eq "${RESULT_59_SIZE}" ]] || fail "sequence 59 result size changed"
[[ "$(sha256sum "${RESULT_59}" | awk '{print $1}')" = "${RESULT_59_SHA}" ]] || fail "sequence 59 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_59.txt)" = "${RESULT_59_COMMIT}" ]] || fail "sequence 59 result commit changed"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_59_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_59.txt" ]] || fail "sequence 59 result commit surface changed"
git merge-base --is-ancestor "${MONITOR_59_COMMIT}" "${RESULT_59_COMMIT}" || fail "sequence 59 command is not an ancestor of its result"
[[ "$(git log -1 --format=%H "${RESULT_59_COMMIT}^" -- inbox/kalmannet-tukf09-455/cmd.sh)" = "${MONITOR_59_COMMIT}" ]] || fail "sequence 59 command lineage changed"
[[ "$(git show "${MONITOR_59_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${MONITOR_59_COMMAND_SHA}" ]] || fail "sequence 59 monitor command hash changed"

"${PYTHON}" -B - "${RESULT_59}" "${TRAINING_JOB_ID}" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
job_id = sys.argv[2]
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=59"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=0"
assert lines[-1].startswith("### finished=")
assert any(line.startswith(f"{job_id}|tukf09-455-v2r4-neural|hgpu8|FAILED|1:0|ngu202|00:00:08|") for line in lines)
assert "LOG=training-217409.out SIZE=0 SHA256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" in lines
assert "LOG=training-217409.err SIZE=1668 SHA256=255f1041ddcdbaeeb0dd87ea2ff40c4b28462c3703e86baf59e18b7e74f4faf9" in lines
assert "RuntimeError: local filter installation final manifest changed" in lines
assert "NEURAL_OUTPUT_ROOT=ABSENT" in lines
assert "TRAINING_VERIFICATION=ABSENT" in lines
assert "TUKF09_455_A800_EXCLUSIVE_V2R4_NEURAL_TRAINING_TERMINAL_NONPASS state=FAILED exit_code=1:0" in lines
PY

echo "=== IMMUTABLE TRAINING JOB RECORD ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${ROOT}/logs" "${ROOT}/status" "${TRAINING_SUBMISSION_LOCK}"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing, linked, or irregular: ${item}"
done
for item in "${TRAINING_JOB_ID_FILE}" "${ADMISSION}" "${TRAINING_SCRIPT}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "required file missing, linked, or irregular: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "required file hard-link count changed: ${item}"
done
[[ "$(stat -c '%a' "${TRAINING_JOB_ID_FILE}")" = "444" ]] || fail "training job id record mode changed"
[[ "$(tr -d '\r\n' < "${TRAINING_JOB_ID_FILE}")" = "${TRAINING_JOB_ID}" ]] || fail "training job id record mismatch"
[[ "$(sha256sum "${ADMISSION}" | awk '{print $1}')" = "${ADMISSION_SHA}" ]] || fail "technical admission hash changed"
[[ "$(sha256sum "${TRAINING_SCRIPT}" | awk '{print $1}')" = "${TRAINING_SCRIPT_SHA}" ]] || fail "training Slurm wrapper hash changed"
[[ ! -e "${ROOT}/status/PREPARATION_FAILED.json" && ! -L "${ROOT}/status/PREPARATION_FAILED.json" ]] || fail "preparation failure marker appeared"

echo "=== FORMAL EVALUATION HOLD ==="
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output exists: ${name}"
done

echo "=== SLURM TRAINING STATE ==="
sacct_output=$(sacct -j "${TRAINING_JOB_ID}" -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,NodeList,Elapsed,Start,End 2>&1) || fail "sacct failed: ${sacct_output}"
printf '%s\n' "${sacct_output}"
job_row=$(printf '%s\n' "${sacct_output}" | awk -F'|' -v id="${TRAINING_JOB_ID}" '$1==id {print; found=1} END {exit(found ? 0 : 1)}') || fail "exact training job row missing"
recorded_name=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $2}')
state=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $4}')
exit_code=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $5}')
[[ "${recorded_name}" = "${TRAINING_JOB_NAME}" ]] || fail "training job name mismatch"
squeue -j "${TRAINING_JOB_ID}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true

set +e
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
set -e
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot inspect current user jobs: ${squeue_output}"
same_name=$(printf '%s\n' "${squeue_output}" | awk -F'|' -v name="${TRAINING_JOB_NAME}" '$2==name {print $0}')
if [[ -n "${same_name}" ]]; then
  unexpected_same_name=$(printf '%s\n' "${same_name}" | awk -F'|' -v id="${TRAINING_JOB_ID}" '$1!=id {print $0}')
  [[ -z "${unexpected_same_name}" ]] || fail "another same-name training job exists: ${unexpected_same_name}"
fi

echo "=== READ-ONLY TRAINING ARTIFACT SNAPSHOT ==="
for log in "${TRAINING_STDOUT}" "${TRAINING_STDERR}"; do
  if [[ -e "${log}" || -L "${log}" ]]; then
    [[ -f "${log}" && ! -L "${log}" ]] || fail "training log is linked or irregular: ${log}"
    [[ "$(stat -c '%h' "${log}")" -eq 1 ]] || fail "training log hard-link count changed: ${log}"
    echo "LOG=$(basename "${log}") SIZE=$(stat -c '%s' "${log}") SHA256=$(sha256sum "${log}" | awk '{print $1}')"
    tail -n 80 "${log}"
  else
    echo "LOG=$(basename "${log}") ABSENT"
  fi
done

if [[ -e "${RESULTS_ROOT}/neural" || -L "${RESULTS_ROOT}/neural" ]]; then
  [[ -d "${RESULTS_ROOT}/neural" && ! -L "${RESULTS_ROOT}/neural" ]] || fail "neural output root is linked or irregular"
  neural_directory_count=$(find "${RESULTS_ROOT}/neural" -mindepth 1 -type d -printf '.' | wc -c)
  neural_file_count=$(find "${RESULTS_ROOT}/neural" -mindepth 1 -type f -printf '.' | wc -c)
  neural_total_bytes=$(find "${RESULTS_ROOT}/neural" -mindepth 1 -type f -printf '%s\n' | awk '{sum+=$1} END{print sum+0}')
  echo "NEURAL_DIRECTORY_COUNT=${neural_directory_count}"
  echo "NEURAL_FILE_COUNT=${neural_file_count}"
  echo "NEURAL_TOTAL_BYTES=${neural_total_bytes}"
else
  echo "NEURAL_OUTPUT_ROOT=ABSENT"
fi

if [[ -e "${TRAINING_VERIFICATION}" || -L "${TRAINING_VERIFICATION}" ]]; then
  [[ -f "${TRAINING_VERIFICATION}" && ! -L "${TRAINING_VERIFICATION}" ]] || fail "training verification is linked or irregular"
  [[ "$(stat -c '%h' "${TRAINING_VERIFICATION}")" -eq 1 ]] || fail "training verification hard-link count changed"
  echo "TRAINING_VERIFICATION_SIZE=$(stat -c '%s' "${TRAINING_VERIFICATION}")"
  echo "TRAINING_VERIFICATION_SHA256=$(sha256sum "${TRAINING_VERIFICATION}" | awk '{print $1}')"
else
  echo "TRAINING_VERIFICATION=ABSENT"
fi

case "${state}" in
  PENDING|RUNNING|CONFIGURING|COMPLETING)
    echo "TUKF09_455_A800_EXCLUSIVE_V2R4_NEURAL_TRAINING_NOT_TERMINAL state=${state} exit_code=${exit_code}"
    ;;
  COMPLETED)
    if [[ "${exit_code}" = "0:0" ]]; then
      echo "TUKF09_455_A800_EXCLUSIVE_V2R4_NEURAL_TRAINING_COMPLETED_REQUIRES_STRICT_RESULT_VERIFICATION"
    else
      echo "TUKF09_455_A800_EXCLUSIVE_V2R4_NEURAL_TRAINING_TERMINAL_NONPASS state=${state} exit_code=${exit_code}"
    fi
    ;;
  *)
    echo "TUKF09_455_A800_EXCLUSIVE_V2R4_NEURAL_TRAINING_TERMINAL_NONPASS state=${state} exit_code=${exit_code}"
    ;;
esac

echo "=== TERMINAL FAILURE FORENSIC GATE ==="
[[ "${state}" = "FAILED" && "${exit_code}" = "1:0" ]] || fail "training terminal state changed"
[[ -f "${TRAINING_STDOUT}" && ! -L "${TRAINING_STDOUT}" && ! -s "${TRAINING_STDOUT}" ]] || fail "training standard output differs from the frozen empty log"
[[ "$(sha256sum "${TRAINING_STDOUT}" | awk '{print $1}')" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]] || fail "training standard output hash changed"
[[ -f "${TRAINING_STDERR}" && ! -L "${TRAINING_STDERR}" ]] || fail "training standard error is missing, linked, or irregular"
[[ "$(stat -c '%s' "${TRAINING_STDERR}")" -eq 1668 ]] || fail "training standard error size changed"
[[ "$(sha256sum "${TRAINING_STDERR}" | awk '{print $1}')" = "255f1041ddcdbaeeb0dd87ea2ff40c4b28462c3703e86baf59e18b7e74f4faf9" ]] || fail "training standard error hash changed"
[[ ! -e "${RESULTS_ROOT}/neural" && ! -L "${RESULTS_ROOT}/neural" ]] || fail "neural output appeared after the frozen pre-training failure"
[[ ! -e "${TRAINING_VERIFICATION}" && ! -L "${TRAINING_VERIFICATION}" ]] || fail "training verification appeared after the frozen pre-training failure"
for item in "${BUILDER}" "${EXECUTION_CONFIG}" "${FILTER_SEAL}" "${ADMISSION}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "forensic input is missing, linked, or irregular: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "forensic input hard-link count changed: ${item}"
done
[[ "$(sha256sum "${BUILDER}" | awk '{print $1}')" = "${BUILDER_SHA}" ]] || fail "runtime bundle verifier hash changed"

"${PYTHON}" -B - "${BUILDER}" "${EXECUTION_CONFIG}" "${ADMISSION}" "${FILTER_SEAL}" <<'PY'
from pathlib import Path
import hashlib
import json
import sys

builder_path, config_path, admission_path, remote_seal_path = map(Path, sys.argv[1:])

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

builder = builder_path.read_text(encoding="utf-8")
config = json.loads(config_path.read_text(encoding="utf-8"))
admission = json.loads(admission_path.read_text(encoding="utf-8"))
local_sha = "b378ffbfde4d24ded8fbb42fdf10fef59eb04100c93879a41b4d538ae36f6ba0"
remote_sha = "6e150cd9feba58ec35562e7fc46e7052f9e433cc5a50ae185593f1960703a55f"
assert config["scientific_identity"]["local_filter_installation_final_manifest"]["sha256"] == local_sha
assert admission["local_filter_installation_final_sha256"] == local_sha
assert admission["remote_filter_installation_final_sha256"] == remote_sha
assert sha256(remote_seal_path) == remote_sha
assert local_sha != remote_sha
assert "if _path_exists(local_filter_path) and _sha256_file(" in builder
assert ") != LOCAL_FILTER_INSTALLATION_FINAL_SHA256:" in builder
assert 'raise RuntimeError("local filter installation final manifest changed")' in builder
assert admission["formal_evaluation_authorized"] is False
for field in (
    "evaluation_array_reads",
    "evaluation_predictions",
    "evaluation_metrics",
    "evaluation_outputs",
):
    assert type(admission[field]) is int and admission[field] == 0
print(json.dumps({
    "admission_remote_filter_seal_sha256": admission["remote_filter_installation_final_sha256"],
    "builder_sha256": sha256(builder_path),
    "failure_class": "runtime_bundle_verifier_rechecks_local_filter_seal_at_remote_mutable_path",
    "formal_evaluation_authorized": admission["formal_evaluation_authorized"],
    "local_frozen_filter_seal_sha256": local_sha,
    "neural_model_units_completed": 0,
    "remote_installed_filter_seal_sha256": sha256(remote_seal_path),
    "same_root_retry_allowed": False,
}, sort_keys=True))
PY

echo "TUKF09_455_A800_EXCLUSIVE_V2R4_PRETRAINING_PORTABILITY_FAILURE_FORENSICALLY_CONFIRMED_NO_NEURAL_OUTPUT_EVALUATION_HOLD"
