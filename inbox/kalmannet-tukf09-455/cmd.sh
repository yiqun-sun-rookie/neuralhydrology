#!/bin/bash
# Acquire and freeze the exact 24-file private-runtime input closure on login4.
# This command downloads only; it does not build, install, stage data, train,
# or run formal evaluation.
set -euo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r4_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
DOWNLOAD_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/download_runtime_inputs_login.sh"
DOWNLOAD_SCRIPT_SHA=e28df1015931452bad98441090a7c1e869500ce77b80feb2970b886705f3f505
STAGE_TOOL="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/stage_and_train.py"
STAGE_TOOL_SHA=b5d06b6cc320d22a3248958f1670840ff9cca1d7c82dfb058746dfd1d173ae1b
ALLOCATION_JOB_ID=217219
ALLOCATION_STDOUT="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.out"
ALLOCATION_STDOUT_SIZE=850
ALLOCATION_STDOUT_SHA=b5bd6d28c1b878ec14c3513ac0965fc701ba8c8625659a7234898ef87489fe02
ALLOCATION_STDERR="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.err"
EMPTY_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
MAILBOX_ROOT="$(pwd -P)"
RESULT_50="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_50.txt"
RESULT_50_COMMIT=4a4dcc876c8f3e0b129cdcbb82d9892cec49a102
RESULT_50_PARENT=99914ccf6363ac08e0ef4ac280e9c2112efc77f3
RESULT_50_SIZE=1777
RESULT_50_SHA=dc2f475ded847c961969eae133a0db992ae233c143e4090c07a1fdf4cd0c4a3a
INSPECTION_COMMAND_SHA=9565739d1d0a1d5a712fa6fde0839bb21cae1123526172515466e7999aaf2e9b
FINAL="${ROOT}/offline_inputs_v2r4"
PENDING="${ROOT}/offline_inputs_v2r4.pending.attempt001"
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== VERIFIED SEQUENCE 50 ALLOCATION EVIDENCE ==="
[[ -f "${RESULT_50}" && ! -L "${RESULT_50}" ]] || fail "sequence 50 result is missing, linked, or irregular"
[[ "$(stat -c '%h' "${RESULT_50}")" -eq 1 ]] || fail "sequence 50 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_50}")" -eq "${RESULT_50_SIZE}" ]] || fail "sequence 50 result size changed"
[[ "$(sha256sum "${RESULT_50}" | awk '{print $1}')" = "${RESULT_50_SHA}" ]] || fail "sequence 50 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_50.txt)" = "${RESULT_50_COMMIT}" ]] || fail "sequence 50 result commit changed"
[[ "$(git rev-parse "${RESULT_50_COMMIT}^")" = "${RESULT_50_PARENT}" ]] || fail "sequence 50 result parent changed"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_50_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_50.txt" ]] || fail "sequence 50 result commit surface changed"
[[ "$(git show "${RESULT_50_PARENT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${INSPECTION_COMMAND_SHA}" ]] || fail "sequence 50 inspection command hash changed"
[[ -x "${PYTHON}" ]] || fail "shared Python launcher missing"

"${PYTHON}" -B - "${RESULT_50}" "${ALLOCATION_JOB_ID}" <<'PY'
import json
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
job_id = sys.argv[2]
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=50"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=0"
assert lines[-1].startswith("### finished=")
assert f"{job_id}|tukf09-455-v2r4-map|hgpu8|COMPLETED|0:0|ngu202|" in "\n".join(lines)
assert "STDOUT_SIZE=850" in lines
assert "STDOUT_SHA256=b5bd6d28c1b878ec14c3513ac0965fc701ba8c8625659a7234898ef87489fe02" in lines
assert "STDERR_SIZE=0" in lines
assert "STDERR_SHA256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" in lines
assert "TUKF09_455_A800_EXCLUSIVE_V2R4_ALLOCATION_PROBE_COMPLETED_VERIFIED" in lines
records = [json.loads(line) for line in lines if line.startswith("{")]
assert len(records) == 1
record = records[0]
assert record["status"] == "GPU_ALLOCATION_MAPPING_PASS"
assert record["cuda_available"] is True
assert record["cuda_device_count"] == 1
assert record["cuda_device_names"] == ["NVIDIA A800-SXM4-80GB"]
assert record["exclusive_node_runtime_evidence_passed"] is True
assert record["slurm_job_id"] == job_id
assert record["slurm_job_node_count"] == 1
assert record["slurm_cpus_on_node"] == 64
assert record["slurm_job_cpus_per_node_normalized"] == 64
assert record["slurm_cpus_per_task"] == 4
assert record["slurm_gpu_allocation_variable_present"] is True
assert record["nvidia_selected_gpu_uuid"] == record["torch_process_gpu_uuid"]
PY

echo "=== DOWNLOAD-ONLY GATES ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${ROOT}/logs" "${ROOT}/status"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing, linked, or irregular: ${item}"
done
for item in "${DOWNLOAD_SCRIPT}" "${STAGE_TOOL}" "${ALLOCATION_STDOUT}" "${ALLOCATION_STDERR}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "required evidence missing, linked, or irregular: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "required evidence hard-link count changed: ${item}"
done
[[ "$(sha256sum "${DOWNLOAD_SCRIPT}" | awk '{print $1}')" = "${DOWNLOAD_SCRIPT_SHA}" ]] || fail "download-only wrapper hash mismatch"
[[ "$(sha256sum "${STAGE_TOOL}" | awk '{print $1}')" = "${STAGE_TOOL_SHA}" ]] || fail "offline-input verifier hash mismatch"
[[ "$(stat -c '%s' "${ALLOCATION_STDOUT}")" -eq "${ALLOCATION_STDOUT_SIZE}" ]] || fail "allocation standard output size mismatch"
[[ "$(sha256sum "${ALLOCATION_STDOUT}" | awk '{print $1}')" = "${ALLOCATION_STDOUT_SHA}" ]] || fail "allocation standard output hash mismatch"
[[ ! -s "${ALLOCATION_STDERR}" ]] || fail "allocation standard error is not empty"
[[ "$(sha256sum "${ALLOCATION_STDERR}" | awk '{print $1}')" = "${EMPTY_SHA}" ]] || fail "allocation standard error hash mismatch"
sacct -j "${ALLOCATION_JOB_ID}" -n -P --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' -v id="${ALLOCATION_JOB_ID}" '$1==id && $2=="tukf09-455-v2r4-map" && $3=="COMPLETED" && $4=="0:0" {ok=1} END {exit(ok ? 0 : 1)}' || fail "allocation probe is not completed with exit code 0:0"

for item in \
  "${ROOT}/runtime_v2r4" \
  "${ROOT}/status/PREPARATION_FAILED.json" \
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
shopt -s nullglob
runtime_pending=("${ROOT}"/runtime_v2r4.pending.*)
shopt -u nullglob
[[ "${#runtime_pending[@]}" -eq 0 ]] || fail "private-runtime pending path already exists"
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output exists: ${name}"
done
[[ ! -e "${FINAL}" && ! -L "${FINAL}" ]] || fail "offline runtime input publication already exists"
[[ ! -e "${PENDING}" && ! -L "${PENDING}" ]] || fail "attempt001 pending path already exists"
[[ ! -e "${ROOT}/status/offline_inputs_download.lock" && ! -L "${ROOT}/status/offline_inputs_download.lock" ]] || fail "offline-input acquisition lock already exists"

echo "=== LOGIN4 LOCKED DOWNLOAD ATTEMPT001 ==="
set +e
"${DOWNLOAD_SCRIPT}" attempt001
download_rc=$?
set -e
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
"${PYTHON}" -B - "${FINAL}/manifest.json" <<'PY'
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
for field in (
    "evaluation_array_reads",
    "evaluation_predictions",
    "evaluation_metrics",
    "evaluation_outputs",
):
    assert type(manifest[field]) is int and manifest[field] == 0
print(json.dumps({
    "acquisition_host": manifest["acquisition_host"],
    "identity_sha256": manifest["identity_sha256"],
    "shared_environment_inventory_sha256": manifest["shared_environment_inventory_sha256"],
    "total_bytes": manifest["total_bytes"],
    "total_file_count": manifest["total_file_count"],
}, sort_keys=True))
PY
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
echo "TUKF09_455_A800_EXCLUSIVE_V2R4_OFFLINE_RUNTIME_INPUTS_DOWNLOADED_AND_VERIFIED"
