#!/bin/bash
# Submit exactly one package-native v2r3 allocation probe before any runtime
# acquisition, preparation, training, or formal evaluation.
set -o pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r3_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
PROBE_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/allocation_probe.slurm"
PROBE_SCRIPT_SHA=2d9d8c12f93d65acea198aa2bb48a01d6030c5aa994d03992f0656d21e0d0c8a
EXECUTION_CONFIG="${PROJECT_ROOT}/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r3.json"
EXECUTION_CONFIG_SHA=51082760aaf8718281270e3b681406ea6b6e83ff2c2c76e4aea0a5174a3b269b
DEPLOYMENT_SUMMARY="${ROOT}/status/deployment_summary.json"
DEPLOYMENT_SUMMARY_SHA=c3b09942506b061d3a31387a820e6cf4dd48c8db2ba7bc13999767d9c4f9bd72
JOB_NAME=tukf09-455-v2r3-map
JOB_ID_FILE="${ROOT}/status/allocation_probe_job_id.txt"
SUBMISSION_LOCK="${ROOT}/status/allocation_probe_submission.lock"
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== IMMUTABLE DEPLOYMENT GATES ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${ROOT}/logs" "${ROOT}/status"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing, linked, or irregular: ${item}"
done
for item in "${PROBE_SCRIPT}" "${EXECUTION_CONFIG}" "${DEPLOYMENT_SUMMARY}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "required deployed file missing, linked, or irregular: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "required deployed file hard-link count changed: ${item}"
done
[[ "$(sha256sum "${PROBE_SCRIPT}" | awk '{print $1}')" = "${PROBE_SCRIPT_SHA}" ]] || fail "package allocation probe hash mismatch"
[[ "$(sha256sum "${EXECUTION_CONFIG}" | awk '{print $1}')" = "${EXECUTION_CONFIG_SHA}" ]] || fail "execution config hash mismatch"
[[ "$(sha256sum "${DEPLOYMENT_SUMMARY}" | awk '{print $1}')" = "${DEPLOYMENT_SUMMARY_SHA}" ]] || fail "deployment summary hash mismatch"
[[ -x "${PYTHON}" ]] || fail "shared Python launcher missing"

if ! "${PYTHON}" -B - "${DEPLOYMENT_SUMMARY}" "${EXECUTION_CONFIG}" "${ROOT}" <<'PY'
import json
import os
from pathlib import Path
import sys

summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
config = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
root = Path(sys.argv[3])
assert summary == {
    "archive_sha256": "90c16f73dc41843f1dc21053f07ec57a56f18dd58fcd70a2e174c5b65ccdcf61",
    "bundle_manifest_sha256": "b64829885d5330feb2c66cc7558b1ea3ea38b1def4ae889566480cb369381f6b",
    "failed_predecessor_root": "/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r2_20260901",
    "formal_evaluation_authorized": False,
    "member_count": 2808,
    "offline_runtime_input_file_count": 0,
    "remote_root": str(root),
    "slurm_job_submitted": False,
    "status": "A800_EXCLUSIVE_V2R3_DEPLOYED_STRICT_BUNDLE_VERIFIED_FORMAL_EVALUATION_HOLD",
}
assert config["schema_version"] == "tukf09_455_basin_hpc_execution_a800_exclusive_v2r3"
assert config["experiment_id"] == "TUKF09_455_BASIN_ZERO_VALIDATION_TARGET_VARIANCE_REVISION_V1"
assert config["status"] == "HPC_TECHNICAL_EXECUTION_FROZEN_FORMAL_EVALUATION_HOLD"
assert config["technical_retry"]["revision"] == "v2r3"
assert config["technical_retry"]["scientific_contract_changed"] is False
assert config["technical_retry"]["formal_evaluation_authorized"] is False
assert config["execution_route"]["formal_evaluation_access"] is False
assert config["execution_route"]["neural_model_parallelism"] == 1
assert config["scientific_identity"]["ordered_basin_count"] == 455
assert config["scientific_identity"]["excluded_basins"] == ["08202700"]
assert config["slurm"]["exclusive_node"] is True
assert config["slurm"]["gpus"] == 1
assert "read_formal_evaluation_arrays" in config["forbidden_actions"]
assert "run_formal_evaluation" in config["forbidden_actions"]
for relative in (
    "offline_inputs_v2r3",
    "runtime_v2r3",
    "status/allocation_probe.json",
    "status/allocation_probe_job_id.txt",
    "status/allocation_probe_submission.lock",
    "status/initial_bundle_verification.json",
    "status/staged_training_sources.json",
    "status/preparation_probe.json",
    "status/hpc_technical_admission.json",
    "status/preparation.lock",
    "status/preparation_job_id.txt",
    "status/training_job_id.txt",
):
    assert not os.path.lexists(root / relative), f"pre-allocation output already exists: {relative}"
results = root / "bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
for name in ("selection", "evaluation", "formal_evaluation"):
    assert not os.path.lexists(results / name), f"forbidden output exists before allocation probe: {name}"
PY
then
  fail "deployed bundle or no-evaluation contract failed semantic verification"
fi

if compgen -G "${ROOT}/logs/allocation-probe-*.out" >/dev/null || compgen -G "${ROOT}/logs/allocation-probe-*.err" >/dev/null; then
  fail "allocation-probe logs already exist"
fi

echo "=== SAME-NAME JOB GATE ==="
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot inspect current jobs: ${squeue_output}"
same_name=$(printf '%s\n' "${squeue_output}" | awk -F'|' -v name="${JOB_NAME}" '$2==name {print $0}')
[[ -z "${same_name}" ]] || fail "same-name allocation probe already exists: ${same_name}"

echo "=== ATOMIC ALLOCATION SUBMISSION LOCK ==="
mkdir "${SUBMISSION_LOCK}" || fail "cannot acquire the allocation submission lock"
[[ -d "${SUBMISSION_LOCK}" && ! -L "${SUBMISSION_LOCK}" ]] || fail "allocation submission lock is linked or irregular"
[[ ! -e "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]] || fail "allocation job id record appeared after lock acquisition"
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot recheck current jobs after lock acquisition: ${squeue_output}"
same_name=$(printf '%s\n' "${squeue_output}" | awk -F'|' -v name="${JOB_NAME}" '$2==name {print $0}')
[[ -z "${same_name}" ]] || fail "same-name allocation probe appeared after lock acquisition: ${same_name}"

echo "=== EXACTLY ONE PACKAGE ALLOCATION PROBE SUBMISSION ==="
submit_output=$(sbatch "${PROBE_SCRIPT}" 2>&1)
submit_rc=$?
printf '%s\n' "${submit_output}"
job_ids=$(printf '%s\n' "${submit_output}" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
job_id_count=$(printf '%s\n' "${job_ids}" | awk 'NF{count++} END{print count+0}')
[[ "${submit_rc}" -eq 0 && "${job_id_count}" -eq 1 ]] || fail "allocation-probe submission not proven exactly once (wrapper_rc=${submit_rc}, parsed_count=${job_id_count})"
job_id=$(printf '%s\n' "${job_ids}" | awk 'NF{print; exit}')
case "${job_id}" in
  ''|*[!0-9]*) fail "invalid allocation-probe job id" ;;
esac
pending="${JOB_ID_FILE}.pending.$$"
( set -o noclobber; printf '%s\n' "${job_id}" > "${pending}" ) || fail "cannot write pending allocation-probe job id"
ln "${pending}" "${JOB_ID_FILE}" || fail "allocation-probe job id target appeared concurrently"
rm "${pending}" || fail "cannot remove pending allocation-probe job id link"
[[ -f "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" && "$(stat -c '%h' "${JOB_ID_FILE}")" -eq 1 ]] || fail "published allocation-probe job id record is irregular"
[[ "$(tr -d '\r\n' < "${JOB_ID_FILE}")" = "${job_id}" ]] || fail "published allocation-probe job id record differs"

echo "=== IMMEDIATE STATE ==="
echo "ALLOCATION_PROBE_JOB_ID=${job_id}"
squeue -j "${job_id}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true
echo "TUKF09_455_A800_EXCLUSIVE_V2R3_ALLOCATION_PROBE_SUBMITTED_ONCE"
