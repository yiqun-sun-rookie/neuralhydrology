#!/bin/bash
# Acquire and freeze the exact 24-file private-runtime input closure on login4.
# This command downloads only; it does not build, install, stage data, train, or evaluate.
set -o pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r3_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
DOWNLOAD_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/download_runtime_inputs_login.sh"
DOWNLOAD_SCRIPT_SHA=92ac63aeb4c3ee84e9088aba965a98962cdaea7cbd8637c7a08244b914c9e5e6
STAGE_TOOL="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/stage_and_train.py"
STAGE_TOOL_SHA=13ca4129a82f587ee12370c837ab7dbe1ea6eb5c19a1c927292d2d81f922de6d
ALLOCATION_JOB_ID=217180
ALLOCATION_STDOUT="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.out"
ALLOCATION_STDOUT_SHA=50164697ba9e3e6f1f6edaaa000eab2eb856290aca57b25f4c1c07421232e64c
ALLOCATION_STDERR="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.err"
EMPTY_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
FINAL="${ROOT}/offline_inputs_v2r3"
PENDING="${ROOT}/offline_inputs_v2r3.pending.attempt001"
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== VERIFIED ALLOCATION AND DOWNLOAD-ONLY GATES ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${ROOT}/logs" "${ROOT}/status"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing, linked, or irregular: ${item}"
done
for item in "${DOWNLOAD_SCRIPT}" "${STAGE_TOOL}" "${ALLOCATION_STDOUT}" "${ALLOCATION_STDERR}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "required evidence missing, linked, or irregular: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "required evidence hard-link count changed: ${item}"
done
[[ "$(sha256sum "${DOWNLOAD_SCRIPT}" | awk '{print $1}')" = "${DOWNLOAD_SCRIPT_SHA}" ]] || fail "download-only wrapper hash mismatch"
[[ "$(sha256sum "${STAGE_TOOL}" | awk '{print $1}')" = "${STAGE_TOOL_SHA}" ]] || fail "offline-input verifier hash mismatch"
[[ "$(sha256sum "${ALLOCATION_STDOUT}" | awk '{print $1}')" = "${ALLOCATION_STDOUT_SHA}" ]] || fail "allocation standard output hash mismatch"
[[ "$(sha256sum "${ALLOCATION_STDERR}" | awk '{print $1}')" = "${EMPTY_SHA}" ]] || fail "allocation standard error hash mismatch"
sacct -j "${ALLOCATION_JOB_ID}" -n -P --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' -v id="${ALLOCATION_JOB_ID}" '$1==id && $2=="tukf09-455-v2r3-map" && $3=="COMPLETED" && $4=="0:0" {ok=1} END {exit(ok ? 0 : 1)}' || fail "allocation probe is not completed with exit code 0:0"

for item in \
  "${ROOT}/runtime_v2r3" \
  "${ROOT}/status/initial_bundle_verification.json" \
  "${ROOT}/status/staged_training_sources.json" \
  "${ROOT}/status/preparation_probe.json" \
  "${ROOT}/status/hpc_technical_admission.json" \
  "${ROOT}/status/preparation.lock" \
  "${ROOT}/status/preparation_job_id.txt" \
  "${ROOT}/status/training_submission.lock" \
  "${ROOT}/status/training_job_id.txt"; do
  [[ ! -e "${item}" && ! -L "${item}" ]] || fail "mutable downstream output already exists: ${item}"
done
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output exists: ${name}"
done
[[ ! -e "${FINAL}" && ! -L "${FINAL}" ]] || fail "offline runtime input publication already exists"
[[ ! -e "${PENDING}" && ! -L "${PENDING}" ]] || fail "attempt001 pending path already exists"
[[ ! -e "${ROOT}/status/offline_inputs_download.lock" && ! -L "${ROOT}/status/offline_inputs_download.lock" ]] || fail "offline-input acquisition lock already exists"

echo "=== LOGIN4 LOCKED DOWNLOAD ATTEMPT001 ==="
"${DOWNLOAD_SCRIPT}" attempt001
download_rc=$?
echo "DOWNLOAD_WRAPPER_EXIT_CODE=${download_rc}"
if [[ "${download_rc}" -ne 0 ]]; then
  echo "=== PRESERVED FAILED DOWNLOAD EVIDENCE ==="
  if [[ -d "${PENDING}" && ! -L "${PENDING}" ]]; then
    du -sb "${PENDING}" || true
    find "${PENDING}" -type f -printf '%P|%s\n' | LC_ALL=C sort || true
    for log in "${PENDING}/evidence/download-stdout.log" "${PENDING}/evidence/download-stderr.log"; do
      if [[ -f "${log}" && ! -L "${log}" ]]; then
        echo "LOG=${log} SHA256=$(sha256sum "${log}" | awk '{print $1}')"
        tail -n 80 "${log}"
      fi
    done
  fi
  exit "${download_rc}"
fi

echo "=== STRICT OFFLINE INPUT PUBLICATION VERIFICATION ==="
[[ -d "${FINAL}" && ! -L "${FINAL}" ]] || fail "final offline input root missing, linked, or irregular"
[[ ! -e "${PENDING}" && ! -L "${PENDING}" ]] || fail "successful pending path was not atomically consumed"
"${PYTHON}" -B "${STAGE_TOOL}" verify-offline-inputs \
  --manifest "${FINAL}/manifest.json" \
  --wheelhouse "${FINAL}/wheelhouse" \
  --sourcehouse "${FINAL}/sourcehouse" >/dev/null || fail "published offline inputs failed strict re-verification"
if ! "${PYTHON}" -B - "${FINAL}/manifest.json" <<'PY'
import json
from pathlib import Path
import sys

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert manifest["status"] == "LOGIN4_LOCKED_RUNTIME_INPUTS_FROZEN_FOR_OFFLINE_SLURM_INSTALLATION"
assert manifest["experiment_id"] == "TUKF09_455_BASIN_ZERO_VALIDATION_TARGET_VARIANCE_REVISION_V1"
assert manifest["acquisition_host_shortname"] == "login4"
assert manifest["runtime_binary_lock_sha256"] == "8bfc922ce4165eb7793f0b4f1afe9a185644858875af6a3bfd21992a23046d9f"
assert manifest["psutil_source_lock_sha256"] == "c021239b1cdeafff41591adec793c79820ad66ec5418dba2570ea8ff2ae60d68"
assert manifest["locked_binary_wheel_count"] == 23
assert manifest["source_archive_count"] == 1
assert manifest["total_file_count"] == 24
assert manifest["total_bytes"] == 2817756909
assert len(manifest["files"]) == 24
assert manifest["download_only_no_build_no_install"] is True
assert manifest["shared_nh_final_modified"] is False
assert manifest["scientific_contract_changed"] is False
assert manifest["formal_evaluation_authorized"] is False
assert manifest["evaluation_array_reads"] == 0
assert manifest["evaluation_outputs"] == 0
print(json.dumps({
    "acquisition_host": manifest["acquisition_host"],
    "identity_sha256": manifest["identity_sha256"],
    "shared_environment_inventory_sha256": manifest["shared_environment_inventory_sha256"],
    "total_bytes": manifest["total_bytes"],
    "total_file_count": manifest["total_file_count"],
}, sort_keys=True))
PY
then
  fail "published offline input manifest failed semantic verification"
fi
echo "OFFLINE_INPUT_MANIFEST_SHA256=$(sha256sum "${FINAL}/manifest.json" | awk '{print $1}')"
echo "OFFLINE_INPUT_ROOT_BYTES=$(du -sb "${FINAL}" | awk '{print $1}')"
for evidence in \
  "${FINAL}/evidence/download-command.txt" \
  "${FINAL}/evidence/download-stdout.log" \
  "${FINAL}/evidence/download-stderr.log" \
  "${FINAL}/evidence/shared-environment-before.json" \
  "${FINAL}/evidence/shared-environment-after.json"; do
  [[ -f "${evidence}" && ! -L "${evidence}" && "$(stat -c '%h' "${evidence}")" -eq 1 ]] || fail "download evidence is irregular: ${evidence}"
  echo "EVIDENCE=$(basename "${evidence}") SIZE=$(stat -c '%s' "${evidence}") SHA256=$(sha256sum "${evidence}" | awk '{print $1}')"
done
cmp --silent "${FINAL}/evidence/shared-environment-before.json" "${FINAL}/evidence/shared-environment-after.json" || fail "shared environment snapshots differ"
echo "TUKF09_455_A800_EXCLUSIVE_V2R3_OFFLINE_RUNTIME_INPUTS_DOWNLOADED_AND_VERIFIED"
