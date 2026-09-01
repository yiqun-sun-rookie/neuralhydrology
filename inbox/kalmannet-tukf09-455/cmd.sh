#!/bin/bash
# Deploy and independently verify the isolated v2r5 runtime-portability repair.
# This command submits no Slurm job, trains no model, and cannot authorize or
# run formal evaluation. The failed v2r4 root and job remain immutable evidence.
set -euo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
PRESERVED_V2R4_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r4_20260901
PRESERVED_V2R4_PROJECT="${PRESERVED_V2R4_ROOT}/bundle/kalmannet"
PRESERVED_V2R4_RESULTS="${PRESERVED_V2R4_PROJECT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
PRESERVED_V2R4_JOB_ID=217409
CAPSULE_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v2_20260901
CAPSULE_DATA_ROOT="${CAPSULE_ROOT}/data/camels_us"
MAILBOX_ROOT="$(pwd -P)"
PAYLOAD="${MAILBOX_ROOT}/payload/kalmannet-tukf09-455/a800-exclusive-v2r5-runtime-portability"
ARCHIVE_NAME=tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r5_formal_training.tar.gz
BUILDER_NAME=build_tukf09_455_a800_exclusive_hpc_bundle_v2r5.py
ARCHIVE_SHA=41b07596b8d2a092cdc5878787c10525e31a18e0d549f523dee1717b8c3d974c
ARCHIVE_SIZE=9911781
OUTER_SHA=918f7dedc6990da454ce308993918714c32512524699a00237c45afe2725391b
OUTER_SIZE=1025203
BUILDER_SHA=294b43a0292a1cad655f207028fdeeb32e434aa221174b90e35843b5f2e90bc6
BUILDER_SIZE=58943
INTERNAL_MANIFEST_SHA=f7c18d0a95849ee1d7d0a64c7a8724b6cf1fc0b84967503bd7ec1b484b239e76
RESULT_60="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_60.txt"
RESULT_60_COMMIT=118564f5b64a4b4e6e21c8cfd32c0eb9b6bc2461
RESULT_60_SIZE=3569
RESULT_60_SHA=127b641be4373d2fc5dcce8eccf6e48c23d6d63e2f5e79a498aa414e75d9bfa8
V2R4_BUILDER_SHA=4ccb9026a4de33f71ae173ef7d64d4839e634529219da2c65cff8fcf045215fd
V2R4_CONFIG_SHA=54bb8226621c440983d1a8f4d1291b9980488296bc9658085abef47efe56b3f6
V2R4_STDOUT_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
V2R4_STDERR_SHA=255f1041ddcdbaeeb0dd87ea2ff40c4b28462c3703e86baf59e18b7e74f4faf9
CAPSULE_DATA_IDENTITY=dd238eebc1696f73f9eee7adf924913ff5a912c8f795f8998255e87408b760da
CAPSULE_MANIFEST_SHA=d5de91725d0da93f3aa4a234f5c103131fad8ef4b3c86f919236b9e42a318547
CAPSULE_READY_SHA=10331991ee26049554a3d18682c907bfb343877311ca053ac696ccfa1c6a8b93
CAPSULE_AUDIT_COMMAND_SHA=3028bfac9f7a09fb060c23caca47578d40518c5b3adb301018dcaaef7b9ce3d4
CAPSULE_AUDIT_RESULT_SHA=8d522b19230c8e33bbf2b87025ffd74f45e3c5f498c77530a9cafc76558db02e
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
COMMAND_SHA256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== PRESERVED V2R4 FAILURE EVIDENCE ==="
[[ -x "${PYTHON}" ]] || fail "shared Python launcher missing"
for item in "${PRESERVED_V2R4_ROOT}" "${PRESERVED_V2R4_PROJECT}" "${CAPSULE_ROOT}" "${CAPSULE_DATA_ROOT}"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "preserved directory missing or linked: ${item}"
done
[[ -f "${RESULT_60}" && ! -L "${RESULT_60}" ]] || fail "sequence 60 forensic result missing or linked"
[[ "$(stat -c '%h' "${RESULT_60}")" -eq 1 ]] || fail "sequence 60 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_60}")" -eq "${RESULT_60_SIZE}" ]] || fail "sequence 60 result size changed"
[[ "$(sha256sum "${RESULT_60}" | awk '{print $1}')" = "${RESULT_60_SHA}" ]] || fail "sequence 60 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_60.txt)" = "${RESULT_60_COMMIT}" ]] || fail "sequence 60 result commit changed"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_60_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_60.txt" ]] || fail "sequence 60 result commit surface changed"
sacct -j "${PRESERVED_V2R4_JOB_ID}" -n -P --format=JobIDRaw,State,ExitCode | \
  awk -F'|' -v id="${PRESERVED_V2R4_JOB_ID}" \
    '$1==id && $2=="FAILED" && $3=="1:0" {ok=1} END {exit(ok ? 0 : 1)}' || \
  fail "preserved v2r4 job state changed"
[[ "$(sha256sum "${PRESERVED_V2R4_PROJECT}/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2r4.py" | awk '{print $1}')" = "${V2R4_BUILDER_SHA}" ]] || fail "v2r4 builder changed"
[[ "$(sha256sum "${PRESERVED_V2R4_PROJECT}/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r4.json" | awk '{print $1}')" = "${V2R4_CONFIG_SHA}" ]] || fail "v2r4 execution config changed"
[[ -f "${PRESERVED_V2R4_ROOT}/logs/training-217409.out" && ! -L "${PRESERVED_V2R4_ROOT}/logs/training-217409.out" ]] || fail "v2r4 stdout missing or linked"
[[ "$(sha256sum "${PRESERVED_V2R4_ROOT}/logs/training-217409.out" | awk '{print $1}')" = "${V2R4_STDOUT_SHA}" ]] || fail "v2r4 stdout changed"
[[ -f "${PRESERVED_V2R4_ROOT}/logs/training-217409.err" && ! -L "${PRESERVED_V2R4_ROOT}/logs/training-217409.err" ]] || fail "v2r4 stderr missing or linked"
[[ "$(sha256sum "${PRESERVED_V2R4_ROOT}/logs/training-217409.err" | awk '{print $1}')" = "${V2R4_STDERR_SHA}" ]] || fail "v2r4 stderr changed"
[[ ! -e "${PRESERVED_V2R4_RESULTS}/neural" && ! -L "${PRESERVED_V2R4_RESULTS}/neural" ]] || fail "v2r4 neural output unexpectedly appeared"
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${PRESERVED_V2R4_RESULTS}/${name}" && ! -L "${PRESERVED_V2R4_RESULTS}/${name}" ]] || fail "forbidden v2r4 evaluation output exists: ${name}"
done

echo "=== NEW ROOT AND SAME-NAME JOB GATES ==="
if [[ -e "${ROOT}" || -L "${ROOT}" ]]; then
  fail "new v2r5 remote root already exists"
fi
set +e
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
set -e
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot inspect current jobs: ${squeue_output}"
if printf '%s\n' "${squeue_output}" | awk -F'|' '$2 ~ /^tukf09-455-v2r5-(map|prepare|neural)$/ {found=1} END {exit(found ? 0 : 1)}'; then
  fail "an existing v2r5 job would conflict with deployment"
fi

echo "=== EXACT PAYLOAD GATE ==="
[[ -d "${PAYLOAD}" && ! -L "${PAYLOAD}" ]] || fail "v2r5 payload missing or linked"
[[ "$(find "${PAYLOAD}" -mindepth 1 -maxdepth 1 | wc -l)" -eq 3 ]] || fail "v2r5 payload surface changed"
for name in "${ARCHIVE_NAME}" bundle_manifest.sha256.json "${BUILDER_NAME}"; do
  [[ -f "${PAYLOAD}/${name}" && ! -L "${PAYLOAD}/${name}" ]] || fail "payload file missing or linked: ${name}"
  [[ "$(stat -c '%h' "${PAYLOAD}/${name}")" -eq 1 ]] || fail "payload file hard-linked: ${name}"
done
[[ "$(stat -c '%s' "${PAYLOAD}/${ARCHIVE_NAME}")" -eq "${ARCHIVE_SIZE}" ]] || fail "archive size changed"
[[ "$(stat -c '%s' "${PAYLOAD}/bundle_manifest.sha256.json")" -eq "${OUTER_SIZE}" ]] || fail "outer manifest size changed"
[[ "$(stat -c '%s' "${PAYLOAD}/${BUILDER_NAME}")" -eq "${BUILDER_SIZE}" ]] || fail "builder size changed"
[[ "$(sha256sum "${PAYLOAD}/${ARCHIVE_NAME}" | awk '{print $1}')" = "${ARCHIVE_SHA}" ]] || fail "archive hash changed"
[[ "$(sha256sum "${PAYLOAD}/bundle_manifest.sha256.json" | awk '{print $1}')" = "${OUTER_SHA}" ]] || fail "outer manifest hash changed"
[[ "$(sha256sum "${PAYLOAD}/${BUILDER_NAME}" | awk '{print $1}')" = "${BUILDER_SHA}" ]] || fail "builder hash changed"

export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
unset PYTHONOPTIMIZE

"${PYTHON}" -B - "${PAYLOAD}/bundle_manifest.sha256.json" \
  "${ARCHIVE_SHA}" "${ARCHIVE_SIZE}" "${BUILDER_SHA}" <<'PY'
import json
from pathlib import Path
import sys

outer = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected = {
    "kalmannet/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2r5.py": sys.argv[4],
    "kalmannet/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r5.json": "5c1cdc50d28fde46b92947a1fa0fb628a177f7ad573fcea4f943d55934a04bc7",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/allocation_probe.slurm": "0a11351349ed45fcbc1f3d8e88d622057315d6a2f1e497d5aef06bcf8d3f11f8",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/download_runtime_inputs_login.sh": "ae29782d7cc69137b66c953909967e9f69f06f421ee5701aac41207b5329ec92",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/probe_gpu.slurm": "6dc414df31eecb2fb8996b88fa050dd61f9d7a33e9427749619c254af7891b48",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/psutil-source.lock": "c021239b1cdeafff41591adec793c79820ad66ec5418dba2570ea8ff2ae60d68",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/runtime-binary.lock": "8bfc922ce4165eb7793f0b4f1afe9a185644858875af6a3bfd21992a23046d9f",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/stage_and_train.py": "b3ba14eae1a32280d94530c316cea4bc8449a9d5bce41f8ca31cec931888bc81",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/submit_training_gpu.slurm": "d679c606425761e64f53e5d1489354afcaef67e4f8b29ddccbdce012a26999b9",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/verify_result.py": "43a54205d220cec2d43ba0c3b862be1e9d0328b60d993e72a0e75d34526520ba",
}
assert outer["schema_version"] == "tukf09_455_a800_exclusive_training_hpc_archive_manifest_v2r5"
assert outer["archive_name"] == "tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r5_formal_training.tar.gz"
assert outer["archive_sha256"] == sys.argv[2]
assert outer["archive_size"] == int(sys.argv[3])
assert outer["member_count"] == 2808
assert outer["admitted_executable_count"] == 30
assert outer["admitted_test_count"] == 12
assert outer["artifact_file_count"] == 2751
assert outer["non_admitted_wrapper_count"] == 9
for member, digest in expected.items():
    assert outer["member_sha256"][member] == digest
assert outer["scientific_contract_sha256"] == "7710594dcc5cce7f087cb70492a6f827c3925a98ea7fa051d26c5ef1660304e1"
assert outer["preflight_final_manifest_sha256"] == "f7e0a3f0708d0498cbaeaa77a044687f20d017ffa316170cd4770fc920b144aa"
assert outer["filter_migration_final_manifest_sha256"] == "029521f6c35980ce40fb0afeb14e2734042734c73f6ed0a33a5c0040311c3eb5"
assert outer["training_admission"]["sha256"] == "6ba3cdd742fc2bdf039c51afc75485c8292f0b999d7fe426cb2ccf69057c1b79"
assert outer["training_admission"]["record_sha256"] == "ca43f2ba9e35b47c76808da925508e75770bc00a37f2a89ba1dcf060017531b4"
for field in (
    "local_results_file_count",
    "camels_raw_file_count",
    "neural_checkpoint_count",
    "formal_selection_output_count",
    "formal_evaluation_output_count",
):
    assert type(outer[field]) is int and outer[field] == 0
PY

echo "=== EXCLUSIVE V2R5 ROOT RESERVATION ==="
mkdir "${ROOT}"
DEPLOYMENT_FAILED="${ROOT}/DEPLOYMENT_FAILED.seq61.json"
freeze_root_on_deployment_failure() {
  local exit_code=$?
  trap - EXIT
  if [[ "${exit_code}" -ne 0 ]]; then
    set +e
    "${PYTHON}" -B - "${DEPLOYMENT_FAILED}" "${exit_code}" "${COMMAND_SHA256}" <<'PY'
import json
import os
from pathlib import Path
import sys

path = Path(sys.argv[1])
payload = {
    "command_sha256": sys.argv[3],
    "exit_code": int(sys.argv[2]),
    "mailbox_sequence": 61,
    "schema_version": "tukf09_455_hpc_deployment_failure_a800_exclusive_v2r5",
    "status": "A800_EXCLUSIVE_V2R5_DEPLOYMENT_FAILED_ROOT_FROZEN",
}
if not os.path.lexists(path):
    content = (json.dumps(payload, sort_keys=True) + "\n").encode("utf-8")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o444)
    try:
        os.write(fd, content)
        os.fsync(fd)
    finally:
        os.close(fd)
    directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)
PY
  fi
  exit "${exit_code}"
}
trap freeze_root_on_deployment_failure EXIT
mkdir "${ROOT}/incoming" "${ROOT}/logs" "${ROOT}/status"

"${PYTHON}" -B - "${PAYLOAD}" "${ROOT}/incoming" \
  "${ARCHIVE_NAME}" "${BUILDER_NAME}" <<'PY'
import hashlib
import os
from pathlib import Path
import stat
import sys

source_root = Path(sys.argv[1])
destination_root = Path(sys.argv[2])
names = (sys.argv[3], "bundle_manifest.sha256.json", sys.argv[4])
for name in names:
    source = source_root / name
    destination = destination_root / name
    assert source.is_file() and not source.is_symlink() and source.stat().st_nlink == 1
    assert not os.path.lexists(destination)
    digest = hashlib.sha256()
    size = 0
    source_fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
    destination_fd = os.open(
        destination,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
        0o600,
    )
    source_info = os.fstat(source_fd)
    destination_info = os.fstat(destination_fd)
    assert stat.S_ISREG(source_info.st_mode) and source_info.st_nlink == 1
    assert stat.S_ISREG(destination_info.st_mode) and destination_info.st_nlink == 1
    with os.fdopen(source_fd, "rb") as reader, os.fdopen(destination_fd, "wb") as writer:
        for block in iter(lambda: reader.read(1024 * 1024), b""):
            writer.write(block)
            digest.update(block)
            size += len(block)
        writer.flush()
        os.fsync(writer.fileno())
    assert destination.is_file() and not destination.is_symlink()
    assert destination.stat().st_nlink == 1
    assert destination.stat().st_size == source.stat().st_size == size
    assert hashlib.sha256(destination.read_bytes()).hexdigest() == digest.hexdigest()
directory_fd = os.open(destination_root, os.O_RDONLY | os.O_DIRECTORY)
try:
    os.fsync(directory_fd)
finally:
    os.close(directory_fd)
PY

[[ "$(sha256sum "${ROOT}/incoming/${ARCHIVE_NAME}" | awk '{print $1}')" = "${ARCHIVE_SHA}" ]] || fail "deployed archive hash changed"
[[ "$(sha256sum "${ROOT}/incoming/bundle_manifest.sha256.json" | awk '{print $1}')" = "${OUTER_SHA}" ]] || fail "deployed outer manifest hash changed"
[[ "$(sha256sum "${ROOT}/incoming/${BUILDER_NAME}" | awk '{print $1}')" = "${BUILDER_SHA}" ]] || fail "deployed builder hash changed"

set -o noclobber
"${PYTHON}" -B "${ROOT}/incoming/${BUILDER_NAME}" \
  --archive "${ROOT}/incoming/${ARCHIVE_NAME}" \
  --extract-to "${ROOT}/bundle" \
  > "${ROOT}/status/deployment_extract_verification.json"
"${PYTHON}" -B "${ROOT}/bundle/kalmannet/scripts/${BUILDER_NAME}" \
  --verify-extracted "${ROOT}/bundle" \
  > "${ROOT}/status/deployment_strict_verification.json"
"${PYTHON}" -B \
  "${ROOT}/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/stage_and_train.py" \
  verify-source-capsule --source-root "${CAPSULE_DATA_ROOT}" \
  > "${ROOT}/status/source_capsule_verification.json"

"${PYTHON}" -B - "${ROOT}" "${ARCHIVE_SHA}" "${OUTER_SHA}" \
  "${INTERNAL_MANIFEST_SHA}" "${COMMAND_SHA256}" "${CAPSULE_DATA_IDENTITY}" \
  "${CAPSULE_MANIFEST_SHA}" "${CAPSULE_READY_SHA}" \
  "${CAPSULE_AUDIT_COMMAND_SHA}" "${CAPSULE_AUDIT_RESULT_SHA}" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import sys

root = Path(sys.argv[1])
archive_sha = sys.argv[2]
outer_sha = sys.argv[3]
internal_sha = sys.argv[4]
command_sha = sys.argv[5]
data_identity = sys.argv[6]
capsule_manifest_sha = sys.argv[7]
capsule_ready_sha = sys.argv[8]
audit_command_sha = sys.argv[9]
audit_result_sha = sys.argv[10]
extracted = json.loads((root / "status/deployment_extract_verification.json").read_text())
strict = json.loads((root / "status/deployment_strict_verification.json").read_text())
capsule = json.loads((root / "status/source_capsule_verification.json").read_text())
assert extracted["status"] == "TUKF09_455_A800_EXCLUSIVE_V2R5_HPC_BUNDLE_VERIFIED"
assert extracted["member_count"] == 2808 and extracted["reused"] is False
assert strict["status"] == "TUKF09_455_A800_EXCLUSIVE_V2R5_HPC_BUNDLE_VERIFIED"
assert strict["member_count"] == 2808
assert strict["formal_evaluation_output_count"] == 0
manifest = root / "bundle/bundle_manifest.json"
assert hashlib.sha256(manifest.read_bytes()).hexdigest() == internal_sha
assert capsule["root"] == "/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v2_20260901"
assert capsule["data_file_count"] == 911
assert capsule["evidence_file_count"] == 3
assert capsule["directory_count"] == 44
assert capsule["data_total_bytes"] == 464792200
assert capsule["data_identity_sha256"] == data_identity
assert capsule["manifest_sha256"] == capsule_manifest_sha
assert capsule["ready_sha256"] == capsule_ready_sha
assert capsule["post_publication_audit_mailbox_sequence"] == 47
assert capsule["post_publication_audit_command_sha256"] == audit_command_sha
assert capsule["post_publication_audit_result_sha256"] == audit_result_sha
for forbidden in (
    root / "offline_inputs_v2r5",
    root / "runtime_v2r5",
    root / "status/PREPARATION_FAILED.json",
    root / "status/allocation_probe.json",
    root / "status/preparation_probe.json",
    root / "status/hpc_technical_admission.json",
    root / "bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1",
    root / "bundle/kalmannet/G:/github/pycharm/projects/neuralhydrology/data/camels_us",
):
    assert not os.path.lexists(forbidden), forbidden
summary = {
    "archive_sha256": archive_sha,
    "outer_manifest_sha256": outer_sha,
    "bundle_manifest_sha256": internal_sha,
    "command_sha256": command_sha,
    "formal_evaluation_authorized": False,
    "evaluation_array_reads": 0,
    "evaluation_predictions": 0,
    "evaluation_metrics": 0,
    "evaluation_outputs": 0,
    "member_count": 2808,
    "deployment_mailbox_sequence": 61,
    "neural_model_units": 0,
    "offline_runtime_input_file_count": 0,
    "preserved_failed_v2r4_job_id": 217409,
    "remote_root": str(root),
    "slurm_job_submitted": False,
    "source_capsule_data_identity_sha256": data_identity,
    "source_capsule_post_publication_audit_mailbox_sequence": 47,
    "status": "A800_EXCLUSIVE_V2R5_RUNTIME_PORTABILITY_REPAIR_DEPLOYED_STRICT_BUNDLE_AND_SOURCE_CAPSULE_VERIFIED_FORMAL_EVALUATION_HOLD",
}
path = root / "status/deployment_summary.json"
content = (json.dumps(summary, sort_keys=True, indent=2) + "\n").encode("utf-8")
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
directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
try:
    os.fsync(directory_fd)
finally:
    os.close(directory_fd)
print(json.dumps(summary, sort_keys=True))
PY

trap - EXIT
echo "TUKF09_455_A800_EXCLUSIVE_V2R5_DEPLOYMENT_COMPLETED_NO_JOB_SUBMITTED_FORMAL_EVALUATION_HOLD"
