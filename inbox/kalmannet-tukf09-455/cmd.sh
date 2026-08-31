#!/bin/bash
# Deploy the immutable v2r3 bundle by exclusive Python byte copies. No Slurm
# job, runtime download, training, or evaluation is started here.
set -eo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r3_20260901
FAILED_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r2_20260901
PRIOR_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r1_20260901
PRIOR_ALLOCATION_JOB_ID=217162
PRIOR_ALLOCATION_STDOUT_SHA=8004a5be9c9f31b664fb15c387dd22cf9dc68dc79d1ec12c31ae398a1af55e5c
EMPTY_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
MAILBOX_ROOT="$(pwd -P)"
PAYLOAD="${MAILBOX_ROOT}/payload/kalmannet-tukf09-455/a800-exclusive-v2r3"
ARCHIVE_NAME=tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r3_formal_training.tar.gz
BUILDER_NAME=build_tukf09_455_a800_exclusive_hpc_bundle_v2r3.py
ARCHIVE_SHA=90c16f73dc41843f1dc21053f07ec57a56f18dd58fcd70a2e174c5b65ccdcf61
ARCHIVE_SIZE=9902337
OUTER_SHA=ddb4242a9154e825c979acea3b6c7b1f895c709ba92e2c9c1ba0bb47ad08b09f
BUILDER_SHA=4da9c6b46da311b88b591cdb6cc327f46c43f19f2147c2de0ab4d8ae0d857d88
INTERNAL_MANIFEST_SHA=b64829885d5330feb2c66cc7558b1ea3ea38b1def4ae889566480cb369381f6b
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

# Freeze the v2r2 compatibility stop: exactly three empty directories, no job.
test -d "${FAILED_ROOT}"
test ! -L "${FAILED_ROOT}"
test "$(du -sb "${FAILED_ROOT}" | awk '{print $1}')" -eq 16384
for directory in incoming logs status; do
  test -d "${FAILED_ROOT}/${directory}"
  test ! -L "${FAILED_ROOT}/${directory}"
done
test "$(find "${FAILED_ROOT}" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 3
test "$(find "${FAILED_ROOT}" -mindepth 1 -type f | wc -l)" -eq 0
test "$(find "${FAILED_ROOT}" -mindepth 1 -type l | wc -l)" -eq 0
if squeue -h -o '%j' | grep -Eq '^tukf09-455-v2r2-(map|prepare|neural)$'; then
  echo "REFUSING_V2R2_JOB" >&2
  exit 80
fi

# Retain the exact successful allocation evidence without reusing its root.
sacct -j "${PRIOR_ALLOCATION_JOB_ID}" -n -P --format=JobIDRaw,State,ExitCode | \
  awk -F'|' -v id="${PRIOR_ALLOCATION_JOB_ID}" '$1==id && $2=="COMPLETED" && $3=="0:0" {ok=1} END {exit(ok ? 0 : 1)}'
test "$(sha256sum "${PRIOR_ROOT}/logs/allocation-probe-${PRIOR_ALLOCATION_JOB_ID}.out" | awk '{print $1}')" = "${PRIOR_ALLOCATION_STDOUT_SHA}"
test "$(sha256sum "${PRIOR_ROOT}/logs/allocation-probe-${PRIOR_ALLOCATION_JOB_ID}.err" | awk '{print $1}')" = "${EMPTY_SHA}"
if squeue -h -o '%j' | grep -Eq '^tukf09-455-v2r3-(map|prepare|neural)$'; then
  echo "REFUSING_EXISTING_V2R3_JOB" >&2
  exit 81
fi

test -d "${PAYLOAD}"
test ! -L "${PAYLOAD}"
test "$(find "${PAYLOAD}" -mindepth 1 -maxdepth 1 | wc -l)" -eq 3
for name in "${ARCHIVE_NAME}" bundle_manifest.sha256.json "${BUILDER_NAME}"; do
  test -f "${PAYLOAD}/${name}"
  test ! -L "${PAYLOAD}/${name}"
  test "$(stat -c '%h' "${PAYLOAD}/${name}")" -eq 1
done
test "$(stat -c '%s' "${PAYLOAD}/${ARCHIVE_NAME}")" -eq "${ARCHIVE_SIZE}"
test "$(sha256sum "${PAYLOAD}/${ARCHIVE_NAME}" | awk '{print $1}')" = "${ARCHIVE_SHA}"
test "$(sha256sum "${PAYLOAD}/bundle_manifest.sha256.json" | awk '{print $1}')" = "${OUTER_SHA}"
test "$(sha256sum "${PAYLOAD}/${BUILDER_NAME}" | awk '{print $1}')" = "${BUILDER_SHA}"
test -x "${PYTHON}"
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
unset PYTHONOPTIMIZE

"${PYTHON}" -B - "${PAYLOAD}/bundle_manifest.sha256.json" "${ARCHIVE_SHA}" "${ARCHIVE_SIZE}" "${BUILDER_SHA}" <<'PY'
import json
from pathlib import Path
import sys

outer = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected = {
    "kalmannet/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2r3.py": sys.argv[4],
    "kalmannet/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r3.json": "51082760aaf8718281270e3b681406ea6b6e83ff2c2c76e4aea0a5174a3b269b",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/allocation_probe.slurm": "2d9d8c12f93d65acea198aa2bb48a01d6030c5aa994d03992f0656d21e0d0c8a",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/download_runtime_inputs_login.sh": "92ac63aeb4c3ee84e9088aba965a98962cdaea7cbd8637c7a08244b914c9e5e6",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/probe_gpu.slurm": "1956333c219cd5d703875dc4125a03bff8eb973ec4ccde69c23788226d651423",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/psutil-source.lock": "c021239b1cdeafff41591adec793c79820ad66ec5418dba2570ea8ff2ae60d68",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/runtime-binary.lock": "8bfc922ce4165eb7793f0b4f1afe9a185644858875af6a3bfd21992a23046d9f",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/stage_and_train.py": "13ca4129a82f587ee12370c837ab7dbe1ea6eb5c19a1c927292d2d81f922de6d",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/submit_training_gpu.slurm": "e8d35b35daf91cd010299871c0f93fdb3ec721ebbd3441c56f09055c32bf139f",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/verify_result.py": "a519e2733485bfaf73a57f591a3a8a55029b809a7f041567ca3660674d2ca893",
}
assert outer["schema_version"] == "tukf09_455_a800_exclusive_training_hpc_archive_manifest_v2r3"
assert outer["archive_name"] == "tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r3_formal_training.tar.gz"
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
assert outer["local_results_file_count"] == 0
assert outer["camels_raw_file_count"] == 0
assert outer["neural_checkpoint_count"] == 0
assert outer["formal_selection_output_count"] == 0
assert outer["formal_evaluation_output_count"] == 0
PY

if [[ -e "${ROOT}" || -L "${ROOT}" ]]; then
  echo "REFUSING_EXISTING_REMOTE_ROOT=${ROOT}" >&2
  exit 82
fi
mkdir "${ROOT}"
mkdir "${ROOT}/incoming" "${ROOT}/logs" "${ROOT}/status"

"${PYTHON}" -B - "${PAYLOAD}" "${ROOT}/incoming" "${ARCHIVE_NAME}" "${BUILDER_NAME}" <<'PY'
import hashlib
import os
from pathlib import Path
import sys

source_root = Path(sys.argv[1])
destination_root = Path(sys.argv[2])
names = (sys.argv[3], "bundle_manifest.sha256.json", sys.argv[4])
for name in names:
    source = source_root / name
    destination = destination_root / name
    assert source.is_file() and not source.is_symlink() and source.stat().st_nlink == 1
    assert not destination.exists() and not destination.is_symlink()
    digest = hashlib.sha256()
    size = 0
    with source.open("rb") as reader, destination.open("xb") as writer:
        while True:
            block = reader.read(1024 * 1024)
            if not block:
                break
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

test "$(stat -c '%s' "${ROOT}/incoming/${ARCHIVE_NAME}")" -eq "${ARCHIVE_SIZE}"
test "$(sha256sum "${ROOT}/incoming/${ARCHIVE_NAME}" | awk '{print $1}')" = "${ARCHIVE_SHA}"
test "$(sha256sum "${ROOT}/incoming/bundle_manifest.sha256.json" | awk '{print $1}')" = "${OUTER_SHA}"
test "$(sha256sum "${ROOT}/incoming/${BUILDER_NAME}" | awk '{print $1}')" = "${BUILDER_SHA}"

"${PYTHON}" -B "${ROOT}/incoming/${BUILDER_NAME}" \
  --archive "${ROOT}/incoming/${ARCHIVE_NAME}" \
  --extract-to "${ROOT}/bundle" \
  > "${ROOT}/status/deployment_extract_verification.json"
"${PYTHON}" -B "${ROOT}/bundle/kalmannet/scripts/${BUILDER_NAME}" \
  --verify-extracted "${ROOT}/bundle" \
  > "${ROOT}/status/deployment_strict_verification.json"

"${PYTHON}" -B - "${ROOT}" "${ARCHIVE_SHA}" "${INTERNAL_MANIFEST_SHA}" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
archive_sha = sys.argv[2]
internal_sha = sys.argv[3]
extracted = json.loads((root / "status/deployment_extract_verification.json").read_text())
strict = json.loads((root / "status/deployment_strict_verification.json").read_text())
assert extracted["status"] == "TUKF09_455_A800_EXCLUSIVE_V2R3_HPC_BUNDLE_VERIFIED"
assert extracted["member_count"] == 2808 and extracted["reused"] is False
assert strict["status"] == "TUKF09_455_A800_EXCLUSIVE_V2R3_HPC_BUNDLE_VERIFIED"
assert strict["member_count"] == 2808
assert strict["formal_evaluation_output_count"] == 0
manifest = root / "bundle/bundle_manifest.json"
login_script = root / "bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/download_runtime_inputs_login.sh"
assert hashlib.sha256(manifest.read_bytes()).hexdigest() == internal_sha
assert login_script.is_file() and not login_script.is_symlink()
assert login_script.stat().st_mode & 0o111
for forbidden in (
    root / "offline_inputs_v2r3",
    root / "runtime_v2r3",
    root / "status/allocation_probe.json",
    root / "status/preparation_probe.json",
    root / "status/hpc_technical_admission.json",
    root / "bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1",
):
    assert not forbidden.exists() and not forbidden.is_symlink(), forbidden
summary = {
    "archive_sha256": archive_sha,
    "bundle_manifest_sha256": internal_sha,
    "failed_predecessor_root": "/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r2_20260901",
    "formal_evaluation_authorized": False,
    "member_count": 2808,
    "offline_runtime_input_file_count": 0,
    "remote_root": str(root),
    "slurm_job_submitted": False,
    "status": "A800_EXCLUSIVE_V2R3_DEPLOYED_STRICT_BUNDLE_VERIFIED_FORMAL_EVALUATION_HOLD",
}
path = root / "status/deployment_summary.json"
with path.open("x", encoding="utf-8", newline="\n") as handle:
    json.dump(summary, handle, sort_keys=True, indent=2)
    handle.write("\n")
print(json.dumps(summary, sort_keys=True))
PY

echo "TUKF09_455_A800_EXCLUSIVE_V2R3_DEPLOYMENT_COMPLETED"
