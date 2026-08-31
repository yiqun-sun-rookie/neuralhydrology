#!/bin/bash
# Submit exactly one v2r3 compute preparation job after the login4 offline
# runtime-input publication passed. No training or formal evaluation is submitted.
set -o pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r3_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
SOURCE_ROOT=/data1/home/sunyiq/neuralhydrology/data/camels_us
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
STAGED_ROOT="${PROJECT_ROOT}/G:/github/pycharm/projects/neuralhydrology/data/camels_us"
PREPARE_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/probe_gpu.slurm"
PREPARE_SCRIPT_SHA=1956333c219cd5d703875dc4125a03bff8eb973ec4ccde69c23788226d651423
STAGE_TOOL="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/stage_and_train.py"
STAGE_TOOL_SHA=13ca4129a82f587ee12370c837ab7dbe1ea6eb5c19a1c927292d2d81f922de6d
EXECUTION_CONFIG="${PROJECT_ROOT}/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r3.json"
EXECUTION_CONFIG_SHA=51082760aaf8718281270e3b681406ea6b6e83ff2c2c76e4aea0a5174a3b269b
DEPLOYMENT_SUMMARY="${ROOT}/status/deployment_summary.json"
DEPLOYMENT_SUMMARY_SHA=c3b09942506b061d3a31387a820e6cf4dd48c8db2ba7bc13999767d9c4f9bd72
OFFLINE_ROOT="${ROOT}/offline_inputs_v2r3"
OFFLINE_MANIFEST="${OFFLINE_ROOT}/manifest.json"
OFFLINE_MANIFEST_SHA=0e9cbcec8ad25db938ceed10460357c248e8f9e59a681cd9c84fef8387fbb339
OFFLINE_IDENTITY_SHA=c354a618962b3d2462a34459396f58d89686adc2fa18281db7d90ce0d9d3a137
ALLOCATION_JOB_ID=217180
ALLOCATION_STDOUT="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.out"
ALLOCATION_STDOUT_SHA=50164697ba9e3e6f1f6edaaa000eab2eb856290aca57b25f4c1c07421232e64c
ALLOCATION_STDERR="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.err"
EMPTY_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
JOB_NAME=tukf09-455-v2r3-prepare
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
  awk -F'|' -v id="${ALLOCATION_JOB_ID}" '$1==id && $2=="tukf09-455-v2r3-map" && $3=="COMPLETED" && $4=="0:0" {ok=1} END {exit(ok ? 0 : 1)}' || fail "package allocation probe is not completed with exit code 0:0"

"${PYTHON}" -B "${STAGE_TOOL}" verify-offline-inputs \
  --manifest "${OFFLINE_MANIFEST}" \
  --wheelhouse "${OFFLINE_ROOT}/wheelhouse" \
  --sourcehouse "${OFFLINE_ROOT}/sourcehouse" >/dev/null || fail "offline inputs failed strict re-verification"
if ! "${PYTHON}" -B - "${OFFLINE_MANIFEST}" "${OFFLINE_IDENTITY_SHA}" <<'PY'
import json
from pathlib import Path
import sys

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert manifest["identity_sha256"] == sys.argv[2]
assert manifest["status"] == "LOGIN4_LOCKED_RUNTIME_INPUTS_FROZEN_FOR_OFFLINE_SLURM_INSTALLATION"
assert manifest["acquisition_host_shortname"] == "login4"
assert manifest["total_file_count"] == 24
assert manifest["total_bytes"] == 2817756909
assert manifest["download_only_no_build_no_install"] is True
assert manifest["shared_nh_final_modified"] is False
assert manifest["scientific_contract_changed"] is False
assert manifest["formal_evaluation_authorized"] is False
assert manifest["evaluation_array_reads"] == 0
assert manifest["evaluation_outputs"] == 0
assert manifest["download_evidence"]["download_stderr"]["sha256"] == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
assert manifest["download_evidence"]["shared_environment_before"]["sha256"] == "2ef463380324c6ab679ea1e08cb220987edf258baffa5d83c89e4f0326c4917f"
assert manifest["download_evidence"]["shared_environment_after"]["sha256"] == "2ef463380324c6ab679ea1e08cb220987edf258baffa5d83c89e4f0326c4917f"
PY
then
  fail "offline input manifest failed semantic verification"
fi
cmp --silent "${OFFLINE_ROOT}/evidence/shared-environment-before.json" "${OFFLINE_ROOT}/evidence/shared-environment-after.json" || fail "shared environment snapshots differ"

echo "=== PRISTINE PREPARATION TARGET GATES ==="
for item in \
  "${ROOT}/runtime_v2r3" \
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
if compgen -G "${ROOT}/runtime_v2r3.pending.*" >/dev/null; then
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

echo "=== EXACTLY ONE OFFLINE PREPARATION SUBMISSION ==="
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
echo "TUKF09_455_A800_EXCLUSIVE_V2R3_OFFLINE_PREPARATION_SUBMITTED_ONCE"
