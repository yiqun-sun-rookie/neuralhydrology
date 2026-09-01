#!/bin/bash
# Submit exactly one v2r5 compute preparation job after the login4 offline
# runtime-input publication passed. This command submits no training and never
# opens formal evaluation.
set -euo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
SOURCE_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v2_20260901/data/camels_us
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
STAGED_ROOT="${PROJECT_ROOT}/G:/github/pycharm/projects/neuralhydrology/data/camels_us"
PREPARE_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/probe_gpu.slurm"
PREPARE_SCRIPT_SHA=6dc414df31eecb2fb8996b88fa050dd61f9d7a33e9427749619c254af7891b48
STAGE_TOOL="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/stage_and_train.py"
STAGE_TOOL_SHA=b3ba14eae1a32280d94530c316cea4bc8449a9d5bce41f8ca31cec931888bc81
EXECUTION_CONFIG="${PROJECT_ROOT}/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r5.json"
EXECUTION_CONFIG_SHA=5c1cdc50d28fde46b92947a1fa0fb628a177f7ad573fcea4f943d55934a04bc7
DEPLOYMENT_SUMMARY="${ROOT}/status/deployment_summary.json"
DEPLOYMENT_SUMMARY_SHA=cb20074c651bc3cb206642c21a89a6c053e3be13fe62ed844f8b4cff6dfe834b
OFFLINE_ROOT="${ROOT}/offline_inputs_v2r5"
OFFLINE_MANIFEST="${OFFLINE_ROOT}/manifest.json"
OFFLINE_MANIFEST_SHA=2507f0ea14c4880c4aad9a3ccd5a2e6e1c5e5be1ee18bd0093c52d5db85acf82
OFFLINE_IDENTITY_SHA=28f30e3ff15639e2d68fcc683deb5a242675f3597541d0f928a5ec37a40aae53
SHARED_ENVIRONMENT_SHA=98e871d36d97b732cfdb23dc053c15eeee1bfa4fbb511e0ef1415dc408757857
ALLOCATION_JOB_ID=217678
ALLOCATION_STDOUT="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.out"
ALLOCATION_STDOUT_SHA=a8d610a54e8b5d91550bd56f8b083fa8301ab30adf57618ea20f258a352ce008
ALLOCATION_STDERR="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.err"
EMPTY_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
MAILBOX_ROOT="$(pwd -P)"
RESULT_65="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_65.txt"
RESULT_65_COMMIT=74bb66f92fa45a6b4261c7a3693258a745b58b20
RESULT_65_COMMAND_COMMIT=c33cdef4294e0e2efa8fcd7b5fe59a7ca17d0534
RESULT_65_COMMAND_SHA=26109cd2fdf922a9143830bf788b991883c710f55070157cc19e58f70174d67e
RESULT_65_SIZE=41488
RESULT_65_SHA=563b48f6825b0565fc504d681a736cad8a8719fb48dc0c54a71ada262aac582d
JOB_NAME=tukf09-455-v2r5-prepare
JOB_ID_FILE="${ROOT}/status/preparation_job_id.txt"
SUBMISSION_LOCK="${ROOT}/status/preparation_submission.lock"
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="${PROJECT_ROOT}"

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== FROZEN SEQUENCE 65 OFFLINE-INPUT EVIDENCE ==="
[[ -x "${PYTHON}" ]] || fail "shared Python launcher missing"
[[ -f "${RESULT_65}" && ! -L "${RESULT_65}" ]] || fail "sequence 65 result missing or linked"
[[ "$(stat -c '%h' "${RESULT_65}")" -eq 1 ]] || fail "sequence 65 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_65}")" -eq "${RESULT_65_SIZE}" ]] || fail "sequence 65 result size changed"
[[ "$(sha256sum "${RESULT_65}" | awk '{print $1}')" = "${RESULT_65_SHA}" ]] || fail "sequence 65 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_65.txt)" = "${RESULT_65_COMMIT}" ]] || fail "sequence 65 result commit changed"
git merge-base --is-ancestor "${RESULT_65_COMMAND_COMMIT}" "${RESULT_65_COMMIT}" || fail "sequence 65 command is not an ancestor of its result"
[[ "$(git log -1 --format=%H "${RESULT_65_COMMIT}^" -- inbox/kalmannet-tukf09-455/cmd.sh)" = "${RESULT_65_COMMAND_COMMIT}" ]] || fail "sequence 65 command was not the last channel command before its result"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_65_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_65.txt" ]] || fail "sequence 65 result commit surface changed"
[[ "$(git show "${RESULT_65_COMMAND_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${RESULT_65_COMMAND_SHA}" ]] || fail "sequence 65 command hash changed"

"${PYTHON}" -B - "${RESULT_65}" <<'PY'
import json
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=65"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=0"
assert lines[-1].startswith("### finished=")
for exact in (
    "TUKF09_455_OFFLINE_RUNTIME_INPUTS_PUBLISHED",
    "DOWNLOAD_WRAPPER_EXIT_CODE=0",
    "OFFLINE_INPUT_MANIFEST_SHA256=2507f0ea14c4880c4aad9a3ccd5a2e6e1c5e5be1ee18bd0093c52d5db85acf82",
    "OFFLINE_INPUT_ROOT_BYTES=2817822168",
    "EVIDENCE=download-command.txt SIZE=326 SHA256=f00c76366a82f580fbeafddc5b089f1051b8c6d4491ffd118a276cdbcfe61f07",
    "EVIDENCE=download-stdout.log SIZE=17124 SHA256=fbc94536f2160f16ed8905cc8828aec30c17695d3d76d021495332d255496c9f",
    "EVIDENCE=download-stderr.log SIZE=0 SHA256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "EVIDENCE=shared-environment-before.json SIZE=12314 SHA256=98e871d36d97b732cfdb23dc053c15eeee1bfa4fbb511e0ef1415dc408757857",
    "EVIDENCE=shared-environment-after.json SIZE=12314 SHA256=98e871d36d97b732cfdb23dc053c15eeee1bfa4fbb511e0ef1415dc408757857",
    "TUKF09_455_A800_EXCLUSIVE_V2R5_OFFLINE_RUNTIME_INPUTS_DOWNLOADED_AND_VERIFIED_FORMAL_EVALUATION_HOLD",
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
    "identity_sha256": "28f30e3ff15639e2d68fcc683deb5a242675f3597541d0f928a5ec37a40aae53",
    "shared_environment_inventory_sha256": "98e871d36d97b732cfdb23dc053c15eeee1bfa4fbb511e0ef1415dc408757857",
    "total_bytes": 2817756909,
    "total_file_count": 24,
}]
PY

echo "=== FROZEN DEPLOYMENT, ALLOCATION, AND OFFLINE-INPUT GATES ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${SOURCE_ROOT}" "${ROOT}/logs" "${ROOT}/status" "${OFFLINE_ROOT}" "${OFFLINE_ROOT}/wheelhouse" "${OFFLINE_ROOT}/sourcehouse"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing or linked: ${item}"
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
  [[ -f "${item}" && ! -L "${item}" ]] || fail "required file missing or linked: ${item}"
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
  awk -F'|' -v id="${ALLOCATION_JOB_ID}" '$1==id && $2=="tukf09-455-v2r5-map" && $3=="COMPLETED" && $4=="0:0" {ok=1} END {exit(ok ? 0 : 1)}' || fail "package allocation probe is not completed with exit code 0:0"

"${PYTHON}" -B "${STAGE_TOOL}" verify-offline-inputs \
  --manifest "${OFFLINE_MANIFEST}" \
  --wheelhouse "${OFFLINE_ROOT}/wheelhouse" \
  --sourcehouse "${OFFLINE_ROOT}/sourcehouse" >/dev/null || fail "offline inputs failed strict re-verification"
"${PYTHON}" -B - "${OFFLINE_MANIFEST}" "${OFFLINE_IDENTITY_SHA}" "${SHARED_ENVIRONMENT_SHA}" "${EXECUTION_CONFIG}" "${DEPLOYMENT_SUMMARY}" <<'PY'
import json
from pathlib import Path
import sys

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
config = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))
deployment = json.loads(Path(sys.argv[5]).read_text(encoding="utf-8"))
assert manifest["schema_version"] == "tukf09_455_hpc_offline_runtime_inputs_a800_exclusive_v2r5"
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
assert config["experiment_id"] == "TUKF09_455_BASIN_ZERO_VALIDATION_TARGET_VARIANCE_REVISION_V1"
assert config["technical_retry"]["revision"] == "v2r5"
assert config["scientific_identity"]["ordered_basin_count"] == 455
assert config["scientific_identity"]["excluded_basins"] == ["08202700"]
assert config["execution_route"]["neural_model_parallelism"] == 1
assert config["execution_route"]["formal_evaluation_access"] is False
assert deployment["neural_model_units"] == 0
assert deployment["formal_evaluation_authorized"] is False
assert deployment["slurm_job_submitted"] is False
for record in (manifest, config["expected_completion"], deployment):
    for field in ("evaluation_array_reads", "evaluation_predictions", "evaluation_metrics", "evaluation_outputs"):
        assert type(record[field]) is int and record[field] == 0
PY
cmp --silent "${OFFLINE_ROOT}/evidence/shared-environment-before.json" "${OFFLINE_ROOT}/evidence/shared-environment-after.json" || fail "shared environment snapshots differ"

echo "=== PRISTINE PREPARATION TARGET GATES ==="
for item in \
  "${ROOT}/runtime_v2r5" \
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
if compgen -G "${ROOT}/runtime_v2r5.pending.*" >/dev/null; then
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
[[ "${submit_rc}" -eq 0 && "${job_id_count}" -eq 1 ]] || fail "preparation submission not proven exactly once"
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
echo "TUKF09_455_A800_EXCLUSIVE_V2R5_OFFLINE_PREPARATION_SUBMITTED_ONCE_FORMAL_EVALUATION_HOLD"
