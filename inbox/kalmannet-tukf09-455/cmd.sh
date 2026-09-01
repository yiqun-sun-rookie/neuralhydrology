#!/bin/bash
# Submit exactly one v2r4 compute preparation job after the login4 offline
# runtime-input publication passed. No training or formal evaluation is
# submitted by this command.
set -euo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r4_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
SOURCE_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v2_20260901/data/camels_us
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
STAGED_ROOT="${PROJECT_ROOT}/G:/github/pycharm/projects/neuralhydrology/data/camels_us"
PREPARE_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/probe_gpu.slurm"
PREPARE_SCRIPT_SHA=cc2e0e09ca896e3254e0d4a34b07e6fe1d9266301c0a89a6eadf826fad7b78db
STAGE_TOOL="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/stage_and_train.py"
STAGE_TOOL_SHA=b5d06b6cc320d22a3248958f1670840ff9cca1d7c82dfb058746dfd1d173ae1b
EXECUTION_CONFIG="${PROJECT_ROOT}/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r4.json"
EXECUTION_CONFIG_SHA=54bb8226621c440983d1a8f4d1291b9980488296bc9658085abef47efe56b3f6
DEPLOYMENT_SUMMARY="${ROOT}/status/deployment_summary.json"
DEPLOYMENT_SUMMARY_SHA=14df1ee8339b15caad43298f396c2f26c174f71718d08681f1cd21de0b8ca794
OFFLINE_ROOT="${ROOT}/offline_inputs_v2r4"
OFFLINE_MANIFEST="${OFFLINE_ROOT}/manifest.json"
OFFLINE_MANIFEST_SHA=269daf813e7306815c549ae879f519d64b970fb014208e930848dd94ff819b2e
OFFLINE_IDENTITY_SHA=e77d74fd1e9103ed9e1fa6ee3bb5f18e905b38eb529dbecce029422296bf3835
SHARED_ENVIRONMENT_SHA=32e63286e5d2d38c16cc93129fb78044a89c764d662bac23a4ed4311aa993942
ALLOCATION_JOB_ID=217219
ALLOCATION_STDOUT="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.out"
ALLOCATION_STDOUT_SHA=b5bd6d28c1b878ec14c3513ac0965fc701ba8c8625659a7234898ef87489fe02
ALLOCATION_STDERR="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.err"
EMPTY_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
MAILBOX_ROOT="$(pwd -P)"
RESULT_51="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_51.txt"
RESULT_51_COMMIT=04d21f5dbd540809eeb06a0b2a6e36eb6b0a1813
RESULT_51_PARENT=dc5ac3da518d68c9f849e3ec3e131ba7e3376d40
RESULT_51_SIZE=41467
RESULT_51_SHA=b704e3f9245d0ddde3699489a79ca7de0c163411523a7d06cf21a02421c024d9
DOWNLOAD_COMMAND_SHA=b9f9ab94d7368ea333dafda8c1c7ab275e6efc53452079328078dc9ad866b2c6
JOB_NAME=tukf09-455-v2r4-prepare
JOB_ID_FILE="${ROOT}/status/preparation_job_id.txt"
SUBMISSION_LOCK="${ROOT}/status/preparation_submission.lock"
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
export PYTHONNOUSERSITE=1
export PYTHONDWRITEBYTECODE=1
export PYTHONPATH="${PROJECT_ROOT}"

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== FROZEN SEQUENCE 51 OFFLINE-INPUT EVIDENCE ==="
[[ -f "${RESULT_51}" && ! -L "${RESULT_51}" ]] || fail "sequence 51 result is missing, linked, or irregular"
[[ "$(stat -c '%h' "${RESULT_51}")" -eq 1 ]] || fail "sequence 51 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_51}")" -eq "${RESULT_51_SIZE}" ]] || fail "sequence 51 result size changed"
[[ "$(sha256sum "${RESULT_51}" | awk '{print $1}')" = "${RESULT_51_SHA}" ]] || fail "sequence 51 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_51.txt)" = "${RESULT_51_COMMIT}" ]] || fail "sequence 51 result commit changed"
[[ "$(git rev-parse "${RESULT_51_COMMIT}^")" = "${RESULT_51_PARENT}" ]] || fail "sequence 51 result parent changed"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_51_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_51.txt" ]] || fail "sequence 51 result commit surface changed"
[[ "$(git show "${RESULT_51_PARENT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${DOWNLOAD_COMMAND_SHA}" ]] || fail "sequence 51 download command hash changed"
[[ -x "${PYTHON}" ]] || fail "shared Python launcher missing"

"${PYTHON}" -B - "${RESULT_51}" <<'PY'
import json
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=51"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=0"
assert lines[-1].startswith("### finished=")
for exact in (
    "TUKF09_455_OFFLINE_RUNTIME_INPUTS_PUBLISHED",
    "DOWNLOAD_WRAPPER_EXIT_CODE=0",
    "OFFLINE_INPUT_MANIFEST_SHA256=269daf813e7306815c549ae879f519d64b970fb014208e930848dd94ff819b2e",
    "OFFLINE_INPUT_ROOT_BYTES=2817822168",
    "EVIDENCE=download-command.txt SIZE=326 SHA256=f00c76366a82f580fbeafddc5b089f1051b8c6d4491ffd118a276cdbcfe61f07",
    "EVIDENCE=download-stdout.log SIZE=17124 SHA256=96a40e247b1521261aa940be448087a941bc3074011cbf367d487d68d4eee02e",
    "EVIDENCE=download-stderr.log SIZE=0 SHA256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "EVIDENCE=shared-environment-before.json SIZE=12314 SHA256=32e63286e5d2d38c16cc93129fb78044a89c764d662bac23a4ed4311aa993942",
    "EVIDENCE=shared-environment-after.json SIZE=12314 SHA256=32e63286e5d2d38c16cc93129fb78044a89c764d662bac23a4ed4311aa993942",
    "TUKF09_455_A800_EXCLUSIVE_V2R4_OFFLINE_RUNTIME_INPUTS_DOWNLOADED_AND_VERIFIED",
):
    assert exact in lines
summaries = []
for line in lines:
    if not line.startswith("{"):
        continue
    value = json.loads(line)
    if set(value) == {
        "acquisition_host",
        "identity_sha256",
        "shared_environment_inventory_sha256",
        "total_bytes",
        "total_file_count",
    }:
        summaries.append(value)
assert summaries == [{
    "acquisition_host": "login4",
    "identity_sha256": "e77d74fd1e9103ed9e1fa6ee3bb5f18e905b38eb529dbecce029422296bf3835",
    "shared_environment_inventory_sha256": "32e63286e5d2d38c16cc93129fb78044a89c764d662bac23a4ed4311aa993942",
    "total_bytes": 2817756909,
    "total_file_count": 24,
}]
PY

echo "=== FROZEN DEPLOYMENT, ALLOCATION, AND OFFLINE-INPUT GATES ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${SOURCE_ROOT}" "${ROOT}/logs" "${ROOT}/status" "${OFFLINE_ROOT}" "${OFFLINE_ROOT}/wheelhouse" "${OFFLINE_ROOT}/sourcehouse"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing, linked, or irregular: ${item}"
done
for item in \
  "${PREPARE_SCRIPT}" \
  "${STAGE_TOOL}" \
  "${EXECUTION_CONFIG}" \
  "${DEPLOYMENT_SUMMARY}" \
  "${OFFLINE_MANIFEST}" \
  "${ROOT}/status/offline_inputs_download.lock" \
  "${ALLOCATION_STDOUT}" \
  "${ALLOCATION_STDERR}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "required file missing, linked, or irregular: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "required file hard-link count changed: ${item}"
done
[[ "$(sha256sum "${PREPARE_SCRIPT}" | awk '{print $1}')" = "${PREPARE_SCRIPT_SHA}" ]] || fail "preparation wrapper hash mismatch"
[[ "$(sha256sum "${STAGE_TOOL}" | awk '{print $1}')" = "${STAGE_TOOL_SHA}" ]] || fail "preparation controller hash mismatch"
[[ "$(sha256sum "${EXECUTION_CONFIG}" | awk '{print $1}')" = "${EXECUTION_CONFIG_SHA}" ]] || fail "execution config hash mismatch"
[[ "$(sha256sum "${DEPLOYMENT_SUMMARY}" | awk '{print $1}')" = "${DEPLOYMENT_SUMMARY_SHA}" ]] || fail "deployment summary hash mismatch"
[[ "$(sha256sum "${OFFLINE_MANIFEST}" | awk '{print $1}')" = "${OFFLINE_MANIFEST_SHA}" ]] || fail "offline input manifest hash mismatch"
[[ "$(sha256sum "${ALLOCATION_STDOUT}" | awk '{print $1}')" = "${ALLOCATION_STDOUT_SHA}" ]] || fail "allocation standard output hash mismatch"
[[ "$(sha256sum "${ALLOCATION_STDERR}" | awk '{print $1}')" = "${EMPTY_SHA}" ]] || fail "allocation standard error hash mismatch"
sacct -j "${ALLOCATION_JOB_ID}" -n -P --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' -v id="${ALLOCATION_JOB_ID}" '$1==id && $2=="tukf09-455-v2r4-map" && $3=="COMPLETED" && $4=="0:0" {ok=1} END {exit(ok ? 0 : 1)}' || fail "package allocation probe is not completed with exit code 0:0"

"${PYTHON}" -B "${STAGE_TOOL}" verify-offline-inputs \
  --manifest "${OFFLINE_MANIFEST}" \
  --wheelhouse "${OFFLINE_ROOT}/wheelhouse" \
  --sourcehouse "${OFFLINE_ROOT}/sourcehouse" >/dev/null || fail "offline inputs failed strict re-verification"
"${PYTHON}" -B - "${OFFLINE_MANIFEST}" "${OFFLINE_IDENTITY_SHA}" "${SHARED_ENVIRONMENT_SHA}" <<'PY'
import json
from pathlib import Path
import sys

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert manifest["identity_sha256"] == sys.argv[2]
assert manifest["shared_environment_inventory_sha256"] == sys.argv[3]
assert manifest["status"] == "LOGIN4_LOCKED_RUNTIME_INPUTS_FROZEN_FOR_OFFLINE_SLURM_INSTALLATION"
assert manifest["acquisition_host_shortname"] == "login4"
assert manifest["locked_binary_wheel_count"] == 23
assert manifest["source_archive_count"] == 1
assert manifest["total_file_count"] == 24
assert manifest["total_bytes"] == 2817756909
assert manifest["download_only_no_build_no_install"] is True
assert manifest["shared_nh_final_modified"] is False
assert manifest["scientific_contract_changed"] is False
assert manifest["formal_evaluation_authorized"] is False
for field in (
    "evaluation_array_reads",
    "evaluation_predictions",
    "evaluation_metrics",
    "evaluation_outputs",
):
    assert type(manifest[field]) is int and manifest[field] == 0
assert manifest["download_evidence"]["download_stderr"]["sha256"] == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
assert manifest["download_evidence"]["shared_environment_before"]["sha256"] == sys.argv[3]
assert manifest["download_evidence"]["shared_environment_after"]["sha256"] == sys.argv[3]
PY
cmp --silent "${OFFLINE_ROOT}/evidence/shared-environment-before.json" "${OFFLINE_ROOT}/evidence/shared-environment-after.json" || fail "shared environment snapshots differ"

echo "=== PRISTINE PREPARATION TARGET GATES ==="
for item in \
  "${ROOT}/runtime_v2r4" \
  "${ROOT}/status/PREPARATION_FAILED.json" \
  "${ROOT}/status/initial_bundle_verification.json" \
  "${ROOT}/status/staged_training_sources.json" \
  "${ROOT}/status/preparation_probe.json" \
  "${ROOT}/status/hpc_technical_admission.json" \
  "${ROOT}/status/preparation.lock" \
  "${SUBMISSION_LOCK}" \
  "${JOB_ID_FILE}" \
  "${ROOT}/status/training_submission.lock" \
  "${ROOT}/status/training_job_id.txt" \
  "${STAGED_ROOT}"; do
  [[ ! -e "${item}" && ! -L "${item}" ]] || fail "preparation target already exists or is linked: ${item}"
done
if compgen -G "${ROOT}/runtime_v2r4.pending.*" >/dev/null; then
  fail "a pending private runtime already exists"
fi
if compgen -G "${ROOT}/status/staged_training_sources.pending-*" >/dev/null; then
  fail "a pending staged-data tree already exists"
fi
if compgen -G "${ROOT}/logs/prepare-*.out" >/dev/null || compgen -G "${ROOT}/logs/prepare-*.err" >/dev/null; then
  fail "preparation logs already exist"
fi
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output exists: ${name}"
done

echo "=== SAME-NAME JOB GATE ==="
set +e
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
set -e
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot inspect current jobs: ${squeue_output}"
same_name=$(printf '%s\n' "${squeue_output}" | awk -F'|' -v name="${JOB_NAME}" '$2==name {print $0}')
[[ -z "${same_name}" ]] || fail "same-name preparation job already exists: ${same_name}"

echo "=== EXCLUSIVE PREPARATION SUBMISSION LOCK ==="
mkdir "${SUBMISSION_LOCK}" || fail "cannot acquire the preparation submission lock"
[[ -d "${SUBMISSION_LOCK}" && ! -L "${SUBMISSION_LOCK}" ]] || fail "preparation submission lock is linked or irregular"
[[ ! -e "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]] || fail "preparation job id record appeared after lock acquisition"
set +e
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
set -e
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot recheck current jobs after lock acquisition: ${squeue_output}"
same_name=$(printf '%s\n' "${squeue_output}" | awk -F'|' -v name="${JOB_NAME}" '$2==name {print $0}')
[[ -z "${same_name}" ]] || fail "same-name preparation job appeared after lock acquisition: ${same_name}"

echo "=== EXACTLY ONE OFFLINE PREPARATION SUBMISSION ==="
set +e
submit_output=$(sbatch "${PREPARE_SCRIPT}" 2>&1)
submit_rc=$?
set -e
printf '%s\n' "${submit_output}"
job_ids=$(printf '%s\n' "${submit_output}" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
job_id_count=$(printf '%s\n' "${job_ids}" | awk 'NF{count++} END{print count+0}')
[[ "${submit_rc}" -eq 0 && "${job_id_count}" -eq 1 ]] || fail "preparation submission not proven exactly once (wrapper_rc=${submit_rc}, parsed_count=${job_id_count})"
job_id=$(printf '%s\n' "${job_ids}" | awk 'NF{print; exit}')
[[ "${job_id}" =~ ^[0-9]+$ ]] || fail "invalid preparation job id"

"${PYTHON}" -B - "${JOB_ID_FILE}" "${job_id}" <<'PY'
import os
from pathlib import Path
import stat
import sys

path = Path(sys.argv[1])
content = (sys.argv[2] + "\n").encode("ascii")
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
try:
    remaining = memoryview(content)
    while remaining:
        written = os.write(fd, remaining)
        assert written > 0
        remaining = remaining[written:]
    os.fsync(fd)
finally:
    os.close(fd)
info = os.lstat(path)
assert stat.S_ISREG(info.st_mode) and info.st_nlink == 1
assert path.read_bytes() == content
directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
try:
    os.fsync(directory_fd)
finally:
    os.close(directory_fd)
PY
chmod 0444 "${JOB_ID_FILE}"

echo "=== IMMEDIATE STATE ==="
echo "PREPARATION_JOB_ID=${job_id}"
squeue -j "${job_id}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true
echo "TUKF09_455_A800_EXCLUSIVE_V2R4_OFFLINE_PREPARATION_SUBMITTED_ONCE"
