#!/bin/bash
set -o pipefail

JOB_ID=212908
MAILBOX=/data1/home/sunyiq/hpc_mailbox
LANDING=/data1/home/sunyiq/id18_output_ensemble_20260826
RESULT_DIR=${LANDING}/results/OE01_objective_output_ensemble_screen_20260826
STDOUT=${LANDING}/logs/oe01-${JOB_ID}.out
STDERR=${LANDING}/logs/oe01-${JOB_ID}.err
RESULT_ARCHIVE=${MAILBOX}/outbox/id18-weight-merge/OE01_OUTPUT_ENSEMBLE_JOB${JOB_ID}_RESULTS.tar.gz

echo "=== WAIT FOR JOB ${JOB_ID} ==="
for INDEX in $(seq 1 120); do
    STATE=$(squeue -h -j "${JOB_ID}" -o '%T' 2>/dev/null)
    [ $((INDEX % 6)) -eq 0 ] && echo "elapsed_seconds=$((INDEX * 10)) queue_state=${STATE:-absent}"
    [ -z "${STATE}" ] && break
    sleep 10
done

echo "=== ACCOUNTING ==="
ACCOUNTING=$(sacct -j "${JOB_ID}" -X --format=JobIDRaw,JobName%24,NodeList%12,State%18,ExitCode%10,Elapsed%12)
echo "${ACCOUNTING}"
echo "${ACCOUNTING}" | awk -v job_id="${JOB_ID}" \
    '$1 == job_id && $4 ~ /^COMPLETED/ && $5 == "0:0" { found = 1 } END { exit !found }' || {
    echo "JOB_NOT_COMPLETED_SUCCESSFULLY"
    exit 3
}

echo "=== EXACT LOGS ==="
echo "stdout=${STDOUT}"
tail -80 "${STDOUT}" 2>/dev/null || true
echo "stderr=${STDERR}"
tail -80 "${STDERR}" 2>/dev/null || true

echo "=== VERIFY RESULT PACKAGE ==="
[ -d "${RESULT_DIR}" ] || { echo "RESULT_DIRECTORY_MISSING=${RESULT_DIR}"; exit 1; }
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

echo "=== DECISION ==="
cat "${RESULT_DIR}/decision.json"
echo "=== METHOD SUMMARY ==="
cat "${RESULT_DIR}/method_summary.csv"
echo "=== PAIRED COMPARISONS ==="
cat "${RESULT_DIR}/paired_comparisons.csv"

echo "=== PACKAGE RESULT ==="
[ ! -e "${RESULT_ARCHIVE}" ] || { echo "RESULT_ARCHIVE_ALREADY_EXISTS=${RESULT_ARCHIVE}"; exit 2; }
cd "${LANDING}" || exit 1
tar -czf "${RESULT_ARCHIVE}" \
    results/OE01_objective_output_ensemble_screen_20260826 \
    logs/oe01-${JOB_ID}.out \
    logs/oe01-${JOB_ID}.err \
    input/safe_predictions_manifest.json \
    src/lstm_fair_531/configs/oe01_objective_output_ensemble_screen_20260826.json \
    src/lstm_fair_531/scripts/run_oe01_output_ensemble_screen.py \
    src/lstm_fair_531/scripts/build_oe01_safe_prediction_snapshot.py \
    bundle_manifest.sha256 || exit 1
sha256sum "${RESULT_ARCHIVE}"
echo "=== MONITOR COMPLETE ==="
exit 0
