#!/usr/bin/env bash
set -euo pipefail
umask 077

REMOTE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901"
FAILED_EXECUTION_ID="DAILY_CAMELS_KNET_PER_BASIN_BUNDLE_DEPLOY1_SEQ7"
FAILED_DIRECTORY="${REMOTE_ROOT}/deployments/${FAILED_EXECUTION_ID}"
FAILED_ARCHIVE="${FAILED_DIRECTORY}/daily_camels_knet_per_basin_pilots_v1.tar.gz"
EXECUTION_ID="DAILY_CAMELS_KNET_PER_BASIN_BUNDLE_DEPLOY2_SEQ8"
DEPLOYMENT_DIRECTORY="${REMOTE_ROOT}/deployments/${EXECUTION_ID}"
SOURCE_DIRECTORY="${DEPLOYMENT_DIRECTORY}/source"
ARCHIVE_PATH="${DEPLOYMENT_DIRECTORY}/daily_camels_knet_per_basin_pilots_v1.tar.gz"
RECEIPT="${DEPLOYMENT_DIRECTORY}/deployment_receipt.txt"
EXPECTED_ARCHIVE_SHA256="31bb37f897cac788c4cd7986f095680da47cfebfffdcda06da038bce3e49e5c6"
EXPECTED_MANIFEST_SHA256="5adbbddc8d119186af4d890d6ce06fd5b8aca10451ff2bf7e88ef074c1f3dee7"
EXPECTED_ARCHIVE_SIZE_BYTES="341452"
EXPECTED_PAYLOAD_MEMBER_COUNT="49"
EXPECTED_EXTRACTED_FILE_COUNT="50"
PROBE_RECEIPT="${REMOTE_ROOT}/probes/DAILY_CAMELS_KNET_PER_BASIN_PILOT_A800_PROBE3_SEQ5/probe_receipt.json"
EXPECTED_PROBE_SHA256="be039638e7b8625aa48ed3c044fff53c4d8c63504605d48c63ff1924167d4f65"

echo '=== BUNDLE DEPLOYMENT RETRY IDENTITY ==='
date --iso-8601=seconds
hostname
echo 'channel=kalmannet-daily-perbasin sequence=8 purpose=retry-deployment-with-correct-payload-versus-manifest-count'
echo 'signals_sent=0 submissions_created=0 optimizer_steps=0 formal_evaluation_access_count=0'

if [[ ! -f "${FAILED_ARCHIVE}" ]]; then
  echo 'sequence-7 verified archive is absent' >&2
  exit 50
fi
if [[ -e "${FAILED_DIRECTORY}/deployment_receipt.txt" ]]; then
  echo 'sequence-7 failure unexpectedly has a completed deployment receipt' >&2
  exit 51
fi
if [[ "$(sha256sum "${FAILED_ARCHIVE}" | awk '{print $1}')" != "${EXPECTED_ARCHIVE_SHA256}" ]] || \
   [[ "$(stat -c '%s' "${FAILED_ARCHIVE}")" != "${EXPECTED_ARCHIVE_SIZE_BYTES}" ]]; then
  echo 'sequence-7 archive identity differs from the frozen bundle' >&2
  exit 52
fi
if [[ "$(find "${FAILED_DIRECTORY}/source" -type f | wc -l | tr -d ' ')" != "${EXPECTED_EXTRACTED_FILE_COUNT}" ]] || \
   [[ "$(sha256sum "${FAILED_DIRECTORY}/source/bundle_manifest.json" | awk '{print $1}')" != "${EXPECTED_MANIFEST_SHA256}" ]]; then
  echo 'sequence-7 evidence is not the single declared count-semantics failure' >&2
  exit 53
fi
if [[ -e "${DEPLOYMENT_DIRECTORY}" ]]; then
  echo "refusing pre-existing retry directory: ${DEPLOYMENT_DIRECTORY}" >&2
  exit 54
fi
if [[ ! -f "${PROBE_RECEIPT}" ]] || \
   [[ "$(sha256sum "${PROBE_RECEIPT}" | awk '{print $1}')" != "${EXPECTED_PROBE_SHA256}" ]]; then
  echo 'passing A800 probe receipt is absent or changed' >&2
  exit 55
fi
python - "${PROBE_RECEIPT}" <<'PY'
import json
from pathlib import Path
import sys

receipt = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected = {
    "status": "PASS",
    "gpu_name": "NVIDIA A800-SXM4-80GB",
    "visible_gpu_count": 1,
    "cuda_matrix_identity_exact": True,
    "optimizer_steps": 0,
    "training_forecast_error_events": 0,
    "formal_evaluation_access_count": 0,
}
for key, value in expected.items():
    if receipt.get(key) != value:
        raise SystemExit(f"probe receipt mismatch for {key}: {receipt.get(key)!r}")
PY

mkdir "${DEPLOYMENT_DIRECTORY}"
cp --reflink=auto --no-clobber "${FAILED_ARCHIVE}" "${ARCHIVE_PATH}"
ACTUAL_ARCHIVE_SHA256="$(sha256sum "${ARCHIVE_PATH}" | awk '{print $1}')"
ACTUAL_ARCHIVE_SIZE_BYTES="$(stat -c '%s' "${ARCHIVE_PATH}")"
if [[ "${ACTUAL_ARCHIVE_SHA256}" != "${EXPECTED_ARCHIVE_SHA256}" ]] || \
   [[ "${ACTUAL_ARCHIVE_SIZE_BYTES}" != "${EXPECTED_ARCHIVE_SIZE_BYTES}" ]]; then
  echo 'copied retry archive differs from the frozen bundle' >&2
  exit 56
fi

mkdir "${SOURCE_DIRECTORY}"
tar --warning=no-timestamp --extract --gzip --file "${ARCHIVE_PATH}" --directory "${SOURCE_DIRECTORY}"
ACTUAL_EXTRACTED_FILE_COUNT="$(find "${SOURCE_DIRECTORY}" -type f | wc -l | tr -d ' ')"
ACTUAL_MANIFEST_SHA256="$(sha256sum "${SOURCE_DIRECTORY}/bundle_manifest.json" | awk '{print $1}')"
if [[ "${ACTUAL_EXTRACTED_FILE_COUNT}" != "${EXPECTED_EXTRACTED_FILE_COUNT}" ]]; then
  echo 'extracted file count differs from payload plus internal manifest' >&2
  exit 57
fi
if [[ "${ACTUAL_MANIFEST_SHA256}" != "${EXPECTED_MANIFEST_SHA256}" ]]; then
  echo 'internal manifest SHA-256 differs from the frozen bundle' >&2
  exit 58
fi

set +u
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="${SOURCE_DIRECTORY}/src:${SOURCE_DIRECTORY}"
INSPECTION_JSON="$(python -u "${SOURCE_DIRECTORY}/scripts/build_daily_camels_knet_per_basin_hpc_bundle.py" --inspect-root "${SOURCE_DIRECTORY}")"
python - "${INSPECTION_JSON}" "${EXPECTED_PAYLOAD_MEMBER_COUNT}" <<'PY'
import json
import sys

inspection = json.loads(sys.argv[1])
if inspection.get("status") != "DEPLOYED_BUNDLE_VERIFIED":
    raise SystemExit("bundle root inspection did not pass")
if inspection.get("member_count") != int(sys.argv[2]):
    raise SystemExit("payload member count differs from the internal manifest")
if inspection.get("historical_evaluation_member_count") != 0:
    raise SystemExit("bundle unexpectedly contains historical evaluation material")
if inspection.get("state_dimensions") != [7, 11, 18]:
    raise SystemExit("pilot state dimensions differ from the frozen bundle")
PY

if [[ -e "${RECEIPT}" ]]; then
  echo 'refusing to replace deployment receipt' >&2
  exit 59
fi
{
  printf 'channel=kalmannet-daily-perbasin\n'
  printf 'sequence=8\n'
  printf 'execution_id=%s\n' "${EXECUTION_ID}"
  printf 'deployment_directory=%s\n' "${DEPLOYMENT_DIRECTORY}"
  printf 'source_directory=%s\n' "${SOURCE_DIRECTORY}"
  printf 'archive_sha256=%s\n' "${ACTUAL_ARCHIVE_SHA256}"
  printf 'archive_size_bytes=%s\n' "${ACTUAL_ARCHIVE_SIZE_BYTES}"
  printf 'manifest_sha256=%s\n' "${ACTUAL_MANIFEST_SHA256}"
  printf 'payload_member_count=%s\n' "${EXPECTED_PAYLOAD_MEMBER_COUNT}"
  printf 'extracted_file_count=%s\n' "${ACTUAL_EXTRACTED_FILE_COUNT}"
  printf 'probe_receipt_sha256=%s\n' "${EXPECTED_PROBE_SHA256}"
  printf 'inspection_json=%s\n' "${INSPECTION_JSON}"
  printf 'submissions_created=0\n'
  printf 'signals_sent=0\n'
  printf 'optimizer_steps=0\n'
  printf 'formal_evaluation_access_count=0\n'
} > "${RECEIPT}"

echo '=== DEPLOYMENT RECEIPT ==='
sha256sum "${RECEIPT}"
cat "${RECEIPT}"
echo '=== DEPLOYMENT RETRY COMPLETE: NO TRAINING, SUBMISSION, OR SIGNAL ==='
