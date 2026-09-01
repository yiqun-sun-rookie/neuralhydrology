#!/bin/bash
# Deploy and independently verify the immutable v2r4 bundle in a never-used
# remote root.  This command submits no Slurm job, trains no model, and does
# not run or authorize formal evaluation.
set -euo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r4_20260901
PRESERVED_V2R3_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r3_20260901
CAPSULE_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v2_20260901
CAPSULE_DATA_ROOT=${CAPSULE_ROOT}/data/camels_us
MAILBOX_ROOT="$(pwd -P)"
PAYLOAD="${MAILBOX_ROOT}/payload/kalmannet-tukf09-455/a800-exclusive-v2r4-fail-closed"
ARCHIVE_NAME=tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r4_formal_training.tar.gz
BUILDER_NAME=build_tukf09_455_a800_exclusive_hpc_bundle_v2r4.py
ARCHIVE_SHA=0f6b3087a976831cb87fc95b3f449318e72f1b198c7c4c13eed04808d43bda7b
ARCHIVE_SIZE=9911107
OUTER_SHA=0db32e49a6f803f375ad9497e1ab4b694a91a4a858074452a79a401a5521ce84
OUTER_SIZE=1025203
BUILDER_SHA=4ccb9026a4de33f71ae173ef7d64d4839e634529219da2c65cff8fcf045215fd
BUILDER_SIZE=57817
INTERNAL_MANIFEST_SHA=97eccb8c689e1c1b22577ba8823a8fb0802a14f10db213f861c5b9e3b504bdc1
CAPSULE_DATA_IDENTITY=dd238eebc1696f73f9eee7adf924913ff5a912c8f795f8998255e87408b760da
CAPSULE_MANIFEST_SHA=d5de91725d0da93f3aa4a234f5c103131fad8ef4b3c86f919236b9e42a318547
CAPSULE_READY_SHA=10331991ee26049554a3d18682c907bfb343877311ca053ac696ccfa1c6a8b93
CAPSULE_AUDIT_COMMAND_SHA=3028bfac9f7a09fb060c23caca47578d40518c5b3adb301018dcaaef7b9ce3d4
CAPSULE_AUDIT_RESULT_SHA=8d522b19230c8e33bbf2b87025ffd74f45e3c5f498c77530a9cafc76558db02e
V2R3_PREPARATION_JOB_ID=217185
V2R3_RESULT_39_SHA=4f303591ac3f5ab71c1327229bf9563ef09ed85c1128e1c8612f61bc2cacf96a
V2R3_RESULT_40_SHA=639edf126e2abe58c082e6f5df58eaf22ac61b1e997a69fa949d2bcc332d45f5
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
COMMAND_SHA256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

test -x "${PYTHON}"
test -d "${PRESERVED_V2R3_ROOT}"
test ! -L "${PRESERVED_V2R3_ROOT}"
test -d "${CAPSULE_ROOT}"
test ! -L "${CAPSULE_ROOT}"
test -d "${CAPSULE_DATA_ROOT}"
test ! -L "${CAPSULE_DATA_ROOT}"
sacct -j "${V2R3_PREPARATION_JOB_ID}" -n -P --format=JobIDRaw,State,ExitCode | \
  awk -F'|' -v id="${V2R3_PREPARATION_JOB_ID}" \
    '$1==id && $2=="FAILED" && $3=="1:0" {ok=1} END {exit(ok ? 0 : 1)}'
for record in result_39.txt result_40.txt result_45.txt result_46.txt result_47.txt; do
  test -f "${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/${record}"
  test ! -L "${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/${record}"
  test "$(stat -c '%h' "${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/${record}")" -eq 1
done
test "$(stat -c '%s' "${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_39.txt")" -eq 22985
test "$(stat -c '%s' "${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_40.txt")" -eq 10154
test "$(stat -c '%s' "${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_45.txt")" -eq 1202
test "$(stat -c '%s' "${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_46.txt")" -eq 388
test "$(stat -c '%s' "${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_47.txt")" -eq 3317
test "$(sha256sum "${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_39.txt" | awk '{print $1}')" = "${V2R3_RESULT_39_SHA}"
test "$(sha256sum "${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_40.txt" | awk '{print $1}')" = "${V2R3_RESULT_40_SHA}"
test "$(sha256sum "${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_45.txt" | awk '{print $1}')" = "78da4a712fdbee06dac78f50f92390c341a3ac83b5da25fee099acb12943b5eb"
test "$(sha256sum "${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_46.txt" | awk '{print $1}')" = "6aa3bce163b3deec6907efce1a6a750418b77b0b3d2ae4f276a79491d3fde804"
test "$(sha256sum "${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_47.txt" | awk '{print $1}')" = "${CAPSULE_AUDIT_RESULT_SHA}"
if squeue -h -o '%j' | grep -Eq '^tukf09-455-v2r4-(map|prepare|neural)$'; then
  echo "REFUSING_EXISTING_V2R4_JOB" >&2
  exit 80
fi
if [[ -e "${ROOT}" || -L "${ROOT}" ]]; then
  echo "REFUSING_EXISTING_REMOTE_ROOT=${ROOT}" >&2
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
test "$(stat -c '%s' "${PAYLOAD}/bundle_manifest.sha256.json")" -eq "${OUTER_SIZE}"
test "$(stat -c '%s' "${PAYLOAD}/${BUILDER_NAME}")" -eq "${BUILDER_SIZE}"
test "$(sha256sum "${PAYLOAD}/${ARCHIVE_NAME}" | awk '{print $1}')" = "${ARCHIVE_SHA}"
test "$(sha256sum "${PAYLOAD}/bundle_manifest.sha256.json" | awk '{print $1}')" = "${OUTER_SHA}"
test "$(sha256sum "${PAYLOAD}/${BUILDER_NAME}" | awk '{print $1}')" = "${BUILDER_SHA}"

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
    "kalmannet/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2r4.py": sys.argv[4],
    "kalmannet/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r4.json": "54bb8226621c440983d1a8f4d1291b9980488296bc9658085abef47efe56b3f6",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/allocation_probe.slurm": "9c6f3992205793070ebbefd0ee2362ceca8fe6c7669b71dc32547fc2e9881dab",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/download_runtime_inputs_login.sh": "e28df1015931452bad98441090a7c1e869500ce77b80feb2970b886705f3f505",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/probe_gpu.slurm": "cc2e0e09ca896e3254e0d4a34b07e6fe1d9266301c0a89a6eadf826fad7b78db",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/psutil-source.lock": "c021239b1cdeafff41591adec793c79820ad66ec5418dba2570ea8ff2ae60d68",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/runtime-binary.lock": "8bfc922ce4165eb7793f0b4f1afe9a185644858875af6a3bfd21992a23046d9f",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/stage_and_train.py": "b5d06b6cc320d22a3248958f1670840ff9cca1d7c82dfb058746dfd1d173ae1b",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/submit_training_gpu.slurm": "27283ab2b4a543ce2cce464afd0a9ad86536d0ed5948eba6ba1b313147ac8fba",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/verify_result.py": "5034b598df9bf84b2ee6c57ea572cf853f11b703feccef821ed3260c867f2941",
}
assert outer["schema_version"] == "tukf09_455_a800_exclusive_training_hpc_archive_manifest_v2r4"
assert outer["archive_name"] == "tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r4_formal_training.tar.gz"
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

# mkdir is the publication reservation.  Any later failure leaves this root in
# place, so a retry at the same v2r4 path is mechanically refused.
mkdir "${ROOT}"
DEPLOYMENT_FAILED="${ROOT}/status/DEPLOYMENT_FAILED.seq48.json"
freeze_root_on_deployment_failure() {
  local exit_code=$?
  local marker="${DEPLOYMENT_FAILED}"
  trap - EXIT
  if [[ "${exit_code}" -ne 0 ]]; then
    set +e
    if [[ ! -d "${ROOT}/status" || -L "${ROOT}/status" ]]; then
      marker="${ROOT}/DEPLOYMENT_FAILED.seq48.json"
    fi
    if [[ ! -e "${marker}" && ! -L "${marker}" ]]; then
      (
        set -o noclobber
        umask 022
        printf '{"command_sha256":"%s","exit_code":%d,"mailbox_sequence":48,"schema_version":"tukf09_455_hpc_deployment_failure_a800_exclusive_v2r4","status":"A800_EXCLUSIVE_V2R4_DEPLOYMENT_FAILED_ROOT_FROZEN"}\n' \
          "${COMMAND_SHA256}" "${exit_code}" > "${marker}"
      )
      if [[ "$?" -eq 0 ]]; then
        chmod 0444 "${marker}"
        sync -f "${marker}"
      else
        echo "The deployment failure marker appeared concurrently; it was not overwritten" >&2
      fi
    fi
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

test "$(stat -c '%s' "${ROOT}/incoming/${ARCHIVE_NAME}")" -eq "${ARCHIVE_SIZE}"
test "$(sha256sum "${ROOT}/incoming/${ARCHIVE_NAME}" | awk '{print $1}')" = "${ARCHIVE_SHA}"
test "$(sha256sum "${ROOT}/incoming/bundle_manifest.sha256.json" | awk '{print $1}')" = "${OUTER_SHA}"
test "$(sha256sum "${ROOT}/incoming/${BUILDER_NAME}" | awk '{print $1}')" = "${BUILDER_SHA}"

set -o noclobber
"${PYTHON}" -B "${ROOT}/incoming/${BUILDER_NAME}" \
  --archive "${ROOT}/incoming/${ARCHIVE_NAME}" \
  --extract-to "${ROOT}/bundle" \
  > "${ROOT}/status/deployment_extract_verification.json"
"${PYTHON}" -B "${ROOT}/bundle/kalmannet/scripts/${BUILDER_NAME}" \
  --verify-extracted "${ROOT}/bundle" \
  > "${ROOT}/status/deployment_strict_verification.json"
"${PYTHON}" -B \
  "${ROOT}/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/stage_and_train.py" \
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
assert extracted["status"] == "TUKF09_455_A800_EXCLUSIVE_V2R4_HPC_BUNDLE_VERIFIED"
assert extracted["member_count"] == 2808 and extracted["reused"] is False
assert strict["status"] == "TUKF09_455_A800_EXCLUSIVE_V2R4_HPC_BUNDLE_VERIFIED"
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
    root / "offline_inputs_v2r4",
    root / "runtime_v2r4",
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
    "deployment_mailbox_sequence": 48,
    "neural_model_units": 0,
    "offline_runtime_input_file_count": 0,
    "remote_root": str(root),
    "slurm_job_submitted": False,
    "source_capsule_data_identity_sha256": data_identity,
    "source_capsule_post_publication_audit_mailbox_sequence": 47,
    "status": "A800_EXCLUSIVE_V2R4_DEPLOYED_STRICT_BUNDLE_AND_SOURCE_CAPSULE_VERIFIED_FORMAL_EVALUATION_HOLD",
}
path = root / "status/deployment_summary.json"
content = (json.dumps(summary, sort_keys=True, indent=2) + "\n").encode("utf-8")
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    remaining = memoryview(content)
    while remaining:
        written = os.write(fd, remaining)
        assert written > 0
        remaining = remaining[written:]
    os.fsync(fd)
finally:
    os.close(fd)
print(json.dumps(summary, sort_keys=True))
PY

echo "TUKF09_455_A800_EXCLUSIVE_V2R4_DEPLOYMENT_COMPLETED_NO_JOB_SUBMITTED"
