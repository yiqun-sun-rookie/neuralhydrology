#!/bin/bash
# Deploy the immutable v2 transport payload into the unique frozen remote root.
set -eo pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_20260831
MAILBOX_ROOT="$(pwd -P)"
PAYLOAD="${MAILBOX_ROOT}/payload/kalmannet-tukf09-455/v2"
ARCHIVE_NAME=tukf09_455_basin_zero_validation_target_variance_revision_v1_formal_training.tar.gz
ARCHIVE_SHA=098782246583e783d7b7ad63abf949e4d8833321d042e9465e9646265fdf26a6
OUTER_SHA=0a25f8059ef3de03432c86a3743852922a127594b5d61c9cb38ec9ba563c7cb5
BUILDER_SHA=2e6b084d4a18fbc8b4c12d94cf19c5fbe615c5b3e56b4223867e08656f04910c

test -d "${PAYLOAD}"
for name in "${ARCHIVE_NAME}" bundle_manifest.sha256.json build_tukf09_455_hpc_bundle.py; do
  test -f "${PAYLOAD}/${name}"
  test ! -L "${PAYLOAD}/${name}"
  test "$(stat -c '%h' "${PAYLOAD}/${name}")" -eq 1
done
test "$(sha256sum "${PAYLOAD}/${ARCHIVE_NAME}" | awk '{print $1}')" = "${ARCHIVE_SHA}"
test "$(sha256sum "${PAYLOAD}/bundle_manifest.sha256.json" | awk '{print $1}')" = "${OUTER_SHA}"
test "$(sha256sum "${PAYLOAD}/build_tukf09_455_hpc_bundle.py" | awk '{print $1}')" = "${BUILDER_SHA}"

if [[ -e "${ROOT}" || -L "${ROOT}" ]]; then
  echo "REFUSING_EXISTING_REMOTE_ROOT=${ROOT}" >&2
  exit 61
fi
mkdir "${ROOT}"
mkdir "${ROOT}/incoming" "${ROOT}/logs" "${ROOT}/status"
cp --no-clobber "${PAYLOAD}/${ARCHIVE_NAME}" "${ROOT}/incoming/${ARCHIVE_NAME}"
cp --no-clobber "${PAYLOAD}/bundle_manifest.sha256.json" "${ROOT}/incoming/bundle_manifest.sha256.json"
cp --no-clobber "${PAYLOAD}/build_tukf09_455_hpc_bundle.py" "${ROOT}/incoming/build_tukf09_455_hpc_bundle.py"
test "$(sha256sum "${ROOT}/incoming/${ARCHIVE_NAME}" | awk '{print $1}')" = "${ARCHIVE_SHA}"
test "$(sha256sum "${ROOT}/incoming/bundle_manifest.sha256.json" | awk '{print $1}')" = "${OUTER_SHA}"
test "$(sha256sum "${ROOT}/incoming/build_tukf09_455_hpc_bundle.py" | awk '{print $1}')" = "${BUILDER_SHA}"

source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || \
source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo "CONDA_FAILED" >&2; exit 62; }
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
PYTHON="${CONDA_PREFIX}/bin/python"

"${PYTHON}" -B "${ROOT}/incoming/build_tukf09_455_hpc_bundle.py" \
  --archive "${ROOT}/incoming/${ARCHIVE_NAME}" \
  --extract-to "${ROOT}/bundle" \
  > "${ROOT}/status/deployment_extract_verification.json"
"${PYTHON}" -B "${ROOT}/bundle/kalmannet/scripts/build_tukf09_455_hpc_bundle.py" \
  --verify-extracted "${ROOT}/bundle" \
  > "${ROOT}/status/deployment_strict_verification.json"

"${PYTHON}" -B - "${ROOT}" "${ARCHIVE_SHA}" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
archive_sha = sys.argv[2]
outer = json.loads((root / "incoming/bundle_manifest.sha256.json").read_text())
extracted = json.loads((root / "status/deployment_extract_verification.json").read_text())
strict = json.loads((root / "status/deployment_strict_verification.json").read_text())
assert outer["archive_sha256"] == archive_sha
assert outer["archive_size"] == 9889592
assert outer["member_count"] == 2807
assert extracted["status"] == "TUKF09_455_HPC_BUNDLE_VERIFIED"
assert extracted["member_count"] == 2807
assert extracted["reused"] is False
assert strict["status"] == "TUKF09_455_HPC_BUNDLE_VERIFIED"
assert strict["member_count"] == 2807
assert strict["formal_evaluation_output_count"] == 0
manifest = root / "bundle/bundle_manifest.json"
assert manifest.is_file() and not manifest.is_symlink()
print(json.dumps({
    "archive_sha256": archive_sha,
    "bundle_manifest_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
    "member_count": strict["member_count"],
    "remote_root": str(root),
    "status": "DEPLOYED_STRICT_BUNDLE_VERIFIED_FORMAL_EVALUATION_HOLD",
}, sort_keys=True))
PY

echo "TUKF09_455_HPC_V2_DEPLOYMENT_COMPLETED"
