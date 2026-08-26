#!/bin/bash
set -o pipefail

MAILBOX=/data1/home/sunyiq/hpc_mailbox
ARCHIVE=${MAILBOX}/payload/id18-weight-merge/oe01-safe-output-ensemble-v1/OE01_SAFE_OUTPUT_ENSEMBLE_20260826.tar.gz
EXPECTED_ARCHIVE_SHA=e05e601fe36f66c18688eae7516d044b2578d28faff3bf255af0e2d4b7a3775f
LANDING=/data1/home/sunyiq/id18_output_ensemble_20260826
SLURM_SCRIPT=${LANDING}/src/lstm_fair_531/hpc/submit_oe01_output_ensemble_screen.slurm

echo "=== OE01 PAYLOAD IDENTITY ==="
date -Is
hostname
echo "archive=${ARCHIVE}"
echo "landing=${LANDING}"

echo "=== VERIFY OUTER ARCHIVE ==="
[ -f "${ARCHIVE}" ] || { echo "ARCHIVE_MISSING=${ARCHIVE}"; exit 1; }
ACTUAL_ARCHIVE_SHA=$(sha256sum "${ARCHIVE}" | awk '{print $1}')
echo "expected_archive_sha256=${EXPECTED_ARCHIVE_SHA}"
echo "actual_archive_sha256=${ACTUAL_ARCHIVE_SHA}"
[ "${ACTUAL_ARCHIVE_SHA}" = "${EXPECTED_ARCHIVE_SHA}" ] || { echo "ARCHIVE_HASH_MISMATCH"; exit 1; }

echo "=== CREATE ISOLATED LANDING ==="
[ ! -e "${LANDING}" ] || { echo "LANDING_ALREADY_EXISTS=${LANDING}"; exit 2; }
mkdir -p "${LANDING}" "${LANDING}/logs" || exit 1
tar -xzf "${ARCHIVE}" -C "${LANDING}" || exit 1

echo "=== VERIFY INTERNAL MANIFEST ==="
cd "${LANDING}" || exit 1
sha256sum -c bundle_manifest.sha256 || exit 1
sed -i 's/\r$//' "${SLURM_SCRIPT}" || exit 1

echo "=== LIGHTWEIGHT CONTRACT CHECK ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source ${HOME}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
export PYTHONPATH="${LANDING}:${PYTHONPATH:-}"
python - <<'PY' || exit 1
import json
from pathlib import Path
from src.lstm_fair_531.scripts.build_oe01_safe_prediction_snapshot import load_contract, sha256_file

root = Path("/data1/home/sunyiq/id18_output_ensemble_20260826")
contract = load_contract(root / "src/lstm_fair_531/configs/oe01_objective_output_ensemble_screen_20260826.json")
manifest = json.loads((root / "input/safe_predictions_manifest.json").read_text(encoding="utf-8"))
snapshot = root / "input/safe_predictions.npz"
assert contract["safe_period"] == {"start": "2005-10-01", "end": "2008-09-30"}
assert manifest["date_start"] == "2005-10-01" and manifest["date_end"] == "2008-09-30"
assert manifest["basin_count"] == 531 and manifest["date_count"] == 1096
assert manifest["npz_sha256"] == sha256_file(snapshot)
print("CONTRACT_OK", contract["experiment_id"], manifest["basin_count"], manifest["date_count"])
print("SNAPSHOT_SHA256", manifest["npz_sha256"])
PY

echo "=== SUBMIT ==="
SUBMIT_OUTPUT=$(sbatch "${SLURM_SCRIPT}" 2>&1)
echo "${SUBMIT_OUTPUT}"
JOB_ID=$(echo "${SUBMIT_OUTPUT}" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "${JOB_ID}" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "JOB_ID=${JOB_ID}"
squeue -j "${JOB_ID}" -o '%.18i %.22j %.10P %.8T %.10M %.20R' || true
echo "=== SUBMISSION COMPLETE ==="
exit 0
