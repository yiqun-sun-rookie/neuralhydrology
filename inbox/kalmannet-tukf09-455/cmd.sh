#!/bin/bash
# Acquire and freeze the exact 24-file private-runtime input closure on login4
# inside the isolated v2r5 root. This command downloads only; it does not build,
# install, stage scientific data, train, or run formal evaluation.
set -euo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
DOWNLOAD_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/download_runtime_inputs_login.sh"
DOWNLOAD_SCRIPT_SHA=ae29782d7cc69137b66c953909967e9f69f06f421ee5701aac41207b5329ec92
STAGE_TOOL="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/stage_and_train.py"
STAGE_TOOL_SHA=b3ba14eae1a32280d94530c316cea4bc8449a9d5bce41f8ca31cec931888bc81
ALLOCATION_JOB_ID=217678
ALLOCATION_STDOUT="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.out"
ALLOCATION_STDOUT_SIZE=850
ALLOCATION_STDOUT_SHA=a8d610a54e8b5d91550bd56f8b083fa8301ab30adf57618ea20f258a352ce008
ALLOCATION_STDERR="${ROOT}/logs/allocation-probe-${ALLOCATION_JOB_ID}.err"
EMPTY_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
MAILBOX_ROOT="$(pwd -P)"
RESULT_64="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_64.txt"
RESULT_64_COMMIT=2a8467ce83a46ee85490d131e8b24b7f1b355b58
RESULT_64_COMMAND_COMMIT=08854523facee4ba49b152190d0d8953600737be
RESULT_64_COMMAND_SHA=61ef88fd15ec7e591ea1f13583b51b5fbe9247c4a082c69ec9af0deb9fb5d931
RESULT_64_SIZE=1800
RESULT_64_SHA=87b07f924f51156830b29ec293b5dc203938da7021ed2358ad057f37cbffc992
FINAL="${ROOT}/offline_inputs_v2r5"
PENDING="${ROOT}/offline_inputs_v2r5.pending.attempt001"
DOWNLOAD_LOCK="${ROOT}/status/offline_inputs_download.lock"
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== FROZEN SEQUENCE 64 ALLOCATION EVIDENCE ==="
[[ -x "${PYTHON}" ]] || fail "shared Python launcher missing"
[[ -f "${RESULT_64}" && ! -L "${RESULT_64}" ]] || fail "sequence 64 result missing or linked"
[[ "$(stat -c '%h' "${RESULT_64}")" -eq 1 ]] || fail "sequence 64 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_64}")" -eq "${RESULT_64_SIZE}" ]] || fail "sequence 64 result size changed"
[[ "$(sha256sum "${RESULT_64}" | awk '{print $1}')" = "${RESULT_64_SHA}" ]] || fail "sequence 64 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_64.txt)" = "${RESULT_64_COMMIT}" ]] || fail "sequence 64 result commit changed"
git merge-base --is-ancestor "${RESULT_64_COMMAND_COMMIT}" "${RESULT_64_COMMIT}" || fail "sequence 64 command is not an ancestor of its result"
[[ "$(git log -1 --format=%H "${RESULT_64_COMMIT}^" -- inbox/kalmannet-tukf09-455/cmd.sh)" = "${RESULT_64_COMMAND_COMMIT}" ]] || fail "sequence 64 command was not the last channel command before its result"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_64_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_64.txt" ]] || fail "sequence 64 result commit surface changed"
[[ "$(git show "${RESULT_64_COMMAND_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${RESULT_64_COMMAND_SHA}" ]] || fail "sequence 64 command hash changed"

"${PYTHON}" -B - "${RESULT_64}" "${ALLOCATION_JOB_ID}" <<'PY'
import json
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
job_id = sys.argv[2]
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=64"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=0"
assert lines[-1].startswith("### finished=")
assert f"{job_id}|tukf09-455-v2r5-map|hgpu8|COMPLETED|0:0|ngu201|" in "\n".join(lines)
assert "STDOUT_SIZE=850" in lines
assert "STDOUT_SHA256=a8d610a54e8b5d91550bd56f8b083fa8301ab30adf57618ea20f258a352ce008" in lines
assert "STDERR_SIZE=0" in lines
assert "STDERR_SHA256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" in lines
assert "TUKF09_455_A800_EXCLUSIVE_V2R5_ALLOCATION_PROBE_COMPLETED_VERIFIED_FORMAL_EVALUATION_HOLD" in lines
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
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing or linked: ${item}"
done
for item in "${DOWNLOAD_SCRIPT}" "${STAGE_TOOL}" "${ALLOCATION_STDOUT}" "${ALLOCATION_STDERR}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "required evidence missing or linked: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "required evidence hard-link count changed: ${item}"
done
[[ "$(sha256sum "${DOWNLOAD_SCRIPT}" | awk '{print $1}')" = "${DOWNLOAD_SCRIPT_SHA}" ]] || fail "download-only wrapper hash mismatch"
[[ "$(sha256sum "${STAGE_TOOL}" | awk '{print $1}')" = "${STAGE_TOOL_SHA}" ]] || fail "offline-input verifier hash mismatch"
[[ "$(stat -c '%s' "${ALLOCATION_STDOUT}")" -eq "${ALLOCATION_STDOUT_SIZE}" ]] || fail "allocation standard output size mismatch"
[[ "$(sha256sum "${ALLOCATION_STDOUT}" | awk '{print $1}')" = "${ALLOCATION_STDOUT_SHA}" ]] || fail "allocation standard output hash mismatch"
[[ ! -s "${ALLOCATION_STDERR}" ]] || fail "allocation standard error is not empty"
[[ "$(sha256sum "${ALLOCATION_STDERR}" | awk '{print $1}')" = "${EMPTY_SHA}" ]] || fail "allocation standard error hash mismatch"
sacct -j "${ALLOCATION_JOB_ID}" -n -P --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' -v id="${ALLOCATION_JOB_ID}" '$1==id && $2=="tukf09-455-v2r5-map" && $3=="COMPLETED" && $4=="0:0" {ok=1} END {exit(ok ? 0 : 1)}' || fail "allocation probe is not completed with exit code 0:0"

for item in \
  "${ROOT}/runtime_v2r5" \
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
runtime_pending=("${ROOT}"/runtime_v2r5.pending.*)
shopt -u nullglob
[[ "${#runtime_pending[@]}" -eq 0 ]] || fail "private-runtime pending path already exists"
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output exists: ${name}"
done
[[ ! -e "${FINAL}" && ! -L "${FINAL}" ]] || fail "offline runtime input publication already exists"
[[ ! -e "${PENDING}" && ! -L "${PENDING}" ]] || fail "attempt001 pending path already exists"
[[ ! -e "${DOWNLOAD_LOCK}" && ! -L "${DOWNLOAD_LOCK}" ]] || fail "offline-input acquisition lock already exists"

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
[[ -d "${FINAL}" && ! -L "${FINAL}" ]] || fail "final offline input root missing or linked"
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
assert manifest["schema_version"] == "tukf09_455_hpc_offline_runtime_inputs_a800_exclusive_v2r5"
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
for field in ("evaluation_array_reads", "evaluation_predictions", "evaluation_metrics", "evaluation_outputs"):
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
echo "TUKF09_455_A800_EXCLUSIVE_V2R5_OFFLINE_RUNTIME_INPUTS_DOWNLOADED_AND_VERIFIED_FORMAL_EVALUATION_HOLD"
