#!/bin/bash
# Submit exactly one package-native allocation probe before mutable preparation.
set -o pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2_20260831
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
PROBE_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2/allocation_probe.slurm"
PROBE_SCRIPT_SHA=0dbee5218b46fb31336e779c6ceb86d1904e3549f22b9bfe5b60ba8bbb02cbb7
EXECUTION_CONFIG="${PROJECT_ROOT}/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2.json"
EXECUTION_CONFIG_SHA=c19d48f679d1eef0c3a21ce67c41a800980d1f51a00360e8adb5d8d9d1d71221
DEPLOYMENT_SUMMARY_SHA=5b7452d455f2a95b35fdfbd14b0ae4ef9746df7e75743cd89fed93e87603025a
SEMANTICS_PROBE_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_a800_exclusive_semantics_probe_v1_20260831_01a055e6
SEMANTICS_PROBE_JSON_SHA=ba5f627b18369e634a558ec9f1edb8cd511464184e5ff33e7bff6acceabefc86
SEMANTICS_PROBE_JOB_ID=217122
JOB_NAME=tukf09-455-a800-v2-map
JOB_ID_FILE="${ROOT}/status/allocation_probe_job_id.txt"

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== IMMUTABLE DEPLOYMENT GATES ==="
[[ -d "${ROOT}" && ! -L "${ROOT}" ]] || fail "deployed root missing, linked, or irregular"
[[ -d "${PROJECT_ROOT}" && ! -L "${PROJECT_ROOT}" ]] || fail "deployed project root missing, linked, or irregular"
for item in "${PROBE_SCRIPT}" "${EXECUTION_CONFIG}" "${ROOT}/status/deployment_summary.json"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "required deployed file missing, linked, or irregular: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "required deployed file hard-link count changed: ${item}"
done
[[ "$(sha256sum "${PROBE_SCRIPT}" | awk '{print $1}')" = "${PROBE_SCRIPT_SHA}" ]] || fail "package allocation probe hash mismatch"
[[ "$(sha256sum "${EXECUTION_CONFIG}" | awk '{print $1}')" = "${EXECUTION_CONFIG_SHA}" ]] || fail "execution config hash mismatch"
[[ "$(sha256sum "${ROOT}/status/deployment_summary.json" | awk '{print $1}')" = "${DEPLOYMENT_SUMMARY_SHA}" ]] || fail "deployment summary hash mismatch"
[[ -f "${SEMANTICS_PROBE_ROOT}/status/allocation_probe.json" && ! -L "${SEMANTICS_PROBE_ROOT}/status/allocation_probe.json" ]] || fail "independent route semantics evidence missing or linked"
[[ "$(sha256sum "${SEMANTICS_PROBE_ROOT}/status/allocation_probe.json" | awk '{print $1}')" = "${SEMANTICS_PROBE_JSON_SHA}" ]] || fail "independent route semantics evidence hash mismatch"
sacct -j "${SEMANTICS_PROBE_JOB_ID}" -n -P --format=JobIDRaw,State,ExitCode | \
  awk -F'|' -v id="${SEMANTICS_PROBE_JOB_ID}" '$1==id && $2=="COMPLETED" && $3=="0:0" {ok=1} END {exit(ok ? 0 : 1)}' || fail "independent route semantics job is not completed with exit code 0:0"

source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || \
source "${HOME}/miniconda3/etc/profile.d/conda.sh" || fail "cannot load conda"
conda activate nh_final || fail "cannot activate nh_final"
PYTHON="${CONDA_PREFIX}/bin/python"
if ! "${PYTHON}" -B - "${ROOT}/status/deployment_summary.json" "${SEMANTICS_PROBE_ROOT}/status/allocation_probe.json" <<'PY'
import json
import os
from pathlib import Path
import sys

summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
probe = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
assert summary["archive_sha256"] == "e08f7daee8f3b61bab520c044568fbce4ee306cbbbdc2a1d3fa45e95357102f7"
assert summary["bundle_manifest_sha256"] == "9f133931bbd2e840fff74358a12d4be2222e359982751cae389a21be8cf317e8"
assert summary["member_count"] == 2807
assert summary["formal_evaluation_authorized"] is False
assert summary["remote_root"] == "/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2_20260831"
assert summary["status"] == "A800_EXCLUSIVE_V2_DEPLOYED_STRICT_BUNDLE_VERIFIED_FORMAL_EVALUATION_HOLD"
assert probe["status"] == "PASS"
assert probe["errors"] == []
assert probe["normalized_allocation"]["exclusive_node_runtime_evidence_passed"] is True
assert probe["pytorch"]["visible_device_count"] == 1
assert probe["pytorch"]["current_process_gpu_uuid"] == probe["nvidia_slurm_selected_gpu"]["uuid"]
root = Path(summary["remote_root"])
for relative in (
    "runtime_v2",
    "status/initial_bundle_verification.json",
    "status/staged_training_sources.json",
    "status/preparation_probe.json",
    "status/hpc_technical_admission.json",
    "status/preparation.lock",
    "status/allocation_probe_job_id.txt",
):
    assert not os.path.lexists(root / relative), f"pre-allocation output already exists: {relative}"
project = root / "bundle" / "kalmannet"
results = project / "results" / "tukf09_455_basin_zero_validation_target_variance_revision_v1"
for name in ("selection", "evaluation", "formal_evaluation"):
    assert not os.path.lexists(results / name), f"forbidden output exists before allocation probe: {name}"
PY
then
  fail "deployed bundle or independent route evidence failed semantic verification"
fi

[[ ! -e "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]] || fail "allocation-probe job id record already exists"

echo "=== SAME-NAME JOB GATE ==="
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot inspect current jobs: ${squeue_output}"
same_name=$(printf '%s\n' "${squeue_output}" | awk -F'|' -v name="${JOB_NAME}" '$2==name {print $0}')
[[ -z "${same_name}" ]] || fail "same-name allocation probe already exists: ${same_name}"

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
rm -f "${pending}" || fail "cannot remove pending allocation-probe job id link"

echo "=== IMMEDIATE STATE ==="
echo "ALLOCATION_PROBE_JOB_ID=${job_id}"
squeue -j "${job_id}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true
echo "TUKF09_455_A800_EXCLUSIVE_V2_ALLOCATION_PROBE_SUBMITTED_ONCE"
