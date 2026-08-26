#!/bin/bash
set -o pipefail

JOB_ID=212908
LANDING=/data1/home/sunyiq/id18_output_ensemble_20260826
RESULT_DIR=${LANDING}/results/OE01_objective_output_ensemble_screen_20260826
TRANSPORT_DIR=${LANDING}/transport/base64_retrieval_v1
ARCHIVE=${TRANSPORT_DIR}/OE01_OUTPUT_ENSEMBLE_JOB212908_RESULTS.tar.gz

echo "=== BUILD PERSISTENT RESULT TRANSPORT ==="
date -Is
hostname
[ -d "${RESULT_DIR}" ] || { echo "RESULT_DIRECTORY_MISSING=${RESULT_DIR}"; exit 1; }
[ ! -e "${TRANSPORT_DIR}" ] || { echo "TRANSPORT_DIRECTORY_ALREADY_EXISTS=${TRANSPORT_DIR}"; exit 2; }
mkdir -p "${TRANSPORT_DIR}" || exit 1

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source ${HOME}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
python - <<'PY' || exit 1
import hashlib
import json
from pathlib import Path

result = Path("/data1/home/sunyiq/id18_output_ensemble_20260826/results/OE01_objective_output_ensemble_screen_20260826")
manifest = json.loads((result / "analysis_manifest.json").read_text(encoding="utf-8"))
for name, expected in manifest["outputs"].items():
    digest = hashlib.sha256((result / name).read_bytes()).hexdigest()
    if digest != expected:
        raise SystemExit(f"HASH_MISMATCH {name} {digest} {expected}")
print("OUTPUT_HASHES_OK", len(manifest["outputs"]))
print("DECISION", manifest["decision"])
print("BASINS", manifest["basin_count"], "DATES", manifest["date_count"])
PY

cd "${LANDING}" || exit 1
tar -czf "${ARCHIVE}" \
    results/OE01_objective_output_ensemble_screen_20260826 \
    logs/oe01-${JOB_ID}.out \
    logs/oe01-${JOB_ID}.err \
    input/safe_predictions_manifest.json \
    src/lstm_fair_531/configs/oe01_objective_output_ensemble_screen_20260826.json \
    src/lstm_fair_531/scripts/run_oe01_output_ensemble_screen.py \
    src/lstm_fair_531/scripts/build_oe01_safe_prediction_snapshot.py \
    bundle_manifest.sha256 || exit 1

ARCHIVE_SHA256=$(sha256sum "${ARCHIVE}" | awk '{print $1}')
ARCHIVE_BYTES=$(wc -c < "${ARCHIVE}" | tr -d '[:space:]')
echo "archive=${ARCHIVE}"
echo "archive_bytes=${ARCHIVE_BYTES}"
echo "archive_sha256=${ARCHIVE_SHA256}"
[ "${ARCHIVE_BYTES}" -le 70000000 ] || { echo "ARCHIVE_TOO_LARGE_FOR_BASE64_TRANSPORT"; exit 3; }

echo "=== ARCHIVE_BASE64_BEGIN ==="
base64 -w 76 "${ARCHIVE}" || exit 1
echo "=== ARCHIVE_BASE64_END ==="
echo "=== TRANSPORT COMPLETE ==="
exit 0
