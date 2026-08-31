#!/bin/bash
# Deploy the immutable A800-exclusive v2 transport payload into its unique root.
set -eo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2_20260831
MAILBOX_ROOT="$(pwd -P)"
PAYLOAD="${MAILBOX_ROOT}/payload/kalmannet-tukf09-455/a800-exclusive-v2"
ARCHIVE_NAME=tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2_formal_training.tar.gz
BUILDER_NAME=build_tukf09_455_a800_exclusive_hpc_bundle_v2.py
ARCHIVE_SHA=e08f7daee8f3b61bab520c044568fbce4ee306cbbbdc2a1d3fa45e95357102f7
ARCHIVE_SIZE=9892748
OUTER_SHA=91aeb7c48ca9046a953071a02010be0f7ce80326bd989c281762f9fe72ab5ac3
BUILDER_SHA=c109ed26ccae9bbf2980269a85230b8f6992e407f58a240b0fc48cd3b5ad7898

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

source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || \
source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo "CONDA_FAILED" >&2; exit 62; }
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
unset PYTHONOPTIMIZE
PYTHON="${CONDA_PREFIX}/bin/python"

"${PYTHON}" -B - "${PAYLOAD}/bundle_manifest.sha256.json" "${ARCHIVE_SHA}" "${ARCHIVE_SIZE}" "${BUILDER_SHA}" <<'PY'
import json
from pathlib import Path
import sys

outer = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
archive_sha = sys.argv[2]
archive_size = int(sys.argv[3])
builder_sha = sys.argv[4]
builder_member = "kalmannet/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2.py"
assert outer["schema_version"] == "tukf09_455_a800_exclusive_training_hpc_archive_manifest_v2"
assert outer["archive_name"] == "tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2_formal_training.tar.gz"
assert outer["experiment_id"] == "TUKF09_455_BASIN_ZERO_VALIDATION_TARGET_VARIANCE_REVISION_V1"
assert outer["purpose"] == "formal_training_only_no_formal_evaluation"
assert outer["archive_sha256"] == archive_sha
assert outer["archive_size"] == archive_size
assert outer["member_count"] == 2807
assert outer["admitted_executable_count"] == 30
assert outer["admitted_test_count"] == 12
assert outer["artifact_file_count"] == 2751
assert outer["config_file_count"] == 6
assert outer["non_admitted_wrapper_count"] == 8
assert outer["member_sha256"][builder_member] == builder_sha
assert outer["scientific_contract_sha256"] == "7710594dcc5cce7f087cb70492a6f827c3925a98ea7fa051d26c5ef1660304e1"
assert outer["preflight_final_manifest_sha256"] == "f7e0a3f0708d0498cbaeaa77a044687f20d017ffa316170cd4770fc920b144aa"
assert outer["filter_migration_final_manifest_sha256"] == "029521f6c35980ce40fb0afeb14e2734042734c73f6ed0a33a5c0040311c3eb5"
assert outer["training_admission"] == {
    "path": "kalmannet/artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/training_admission/training_admission.json",
    "record_sha256": "ca43f2ba9e35b47c76808da925508e75770bc00a37f2a89ba1dcf060017531b4",
    "sha256": "6ba3cdd742fc2bdf039c51afc75485c8292f0b999d7fe426cb2ccf69057c1b79",
}
assert outer["local_results_file_count"] == 0
assert outer["camels_raw_file_count"] == 0
assert outer["neural_checkpoint_count"] == 0
assert outer["formal_selection_output_count"] == 0
assert outer["formal_evaluation_output_count"] == 0
PY

if [[ -e "${ROOT}" || -L "${ROOT}" ]]; then
  echo "REFUSING_EXISTING_REMOTE_ROOT=${ROOT}" >&2
  exit 61
fi
mkdir "${ROOT}"
mkdir "${ROOT}/incoming" "${ROOT}/logs" "${ROOT}/status"
cp --no-clobber "${PAYLOAD}/${ARCHIVE_NAME}" "${ROOT}/incoming/${ARCHIVE_NAME}"
cp --no-clobber "${PAYLOAD}/bundle_manifest.sha256.json" "${ROOT}/incoming/bundle_manifest.sha256.json"
cp --no-clobber "${PAYLOAD}/${BUILDER_NAME}" "${ROOT}/incoming/${BUILDER_NAME}"
for name in "${ARCHIVE_NAME}" bundle_manifest.sha256.json "${BUILDER_NAME}"; do
  test -f "${ROOT}/incoming/${name}"
  test ! -L "${ROOT}/incoming/${name}"
  test "$(stat -c '%h' "${ROOT}/incoming/${name}")" -eq 1
done
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

"${PYTHON}" -B - "${ROOT}" "${ARCHIVE_SHA}" "${ARCHIVE_SIZE}" "${BUILDER_SHA}" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
archive_sha = sys.argv[2]
archive_size = int(sys.argv[3])
builder_sha = sys.argv[4]
outer = json.loads((root / "incoming/bundle_manifest.sha256.json").read_text(encoding="utf-8"))
extracted = json.loads((root / "status/deployment_extract_verification.json").read_text(encoding="utf-8"))
strict = json.loads((root / "status/deployment_strict_verification.json").read_text(encoding="utf-8"))
assert outer["archive_sha256"] == archive_sha
assert outer["archive_size"] == archive_size
assert outer["member_count"] == 2807
assert extracted["status"] == "TUKF09_455_A800_EXCLUSIVE_V2_HPC_BUNDLE_VERIFIED"
assert extracted["member_count"] == 2807
assert extracted["reused"] is False
assert strict["status"] == "TUKF09_455_A800_EXCLUSIVE_V2_HPC_BUNDLE_VERIFIED"
assert strict["member_count"] == 2807
assert strict["admitted_executable_count"] == 30
assert strict["admitted_test_count"] == 12
assert strict["artifact_file_count"] == 2751
assert strict["formal_evaluation_output_count"] == 0
builder = root / "bundle/kalmannet/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2.py"
manifest = root / "bundle/bundle_manifest.json"
assert builder.is_file() and not builder.is_symlink()
assert hashlib.sha256(builder.read_bytes()).hexdigest() == builder_sha
assert manifest.is_file() and not manifest.is_symlink()
summary = {
    "archive_sha256": archive_sha,
    "bundle_manifest_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
    "formal_evaluation_authorized": False,
    "member_count": strict["member_count"],
    "remote_root": str(root),
    "status": "A800_EXCLUSIVE_V2_DEPLOYED_STRICT_BUNDLE_VERIFIED_FORMAL_EVALUATION_HOLD",
}
summary_path = root / "status/deployment_summary.json"
with summary_path.open("x", encoding="utf-8", newline="\n") as handle:
    json.dump(summary, handle, ensure_ascii=True, indent=2, sort_keys=True)
    handle.write("\n")
print(json.dumps(summary, sort_keys=True))
PY

echo "TUKF09_455_A800_EXCLUSIVE_V2_DEPLOYMENT_COMPLETED"
