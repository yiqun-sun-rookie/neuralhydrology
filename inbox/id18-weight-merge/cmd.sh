#!/bin/bash
set -o pipefail

LANDING=/data1/home/sunyiq/id18_ties_merge_20260826
JOB_ID=$(cat "${LANDING}/A800_RETRY_NO_PYTEST_JOB_ID.txt" 2>/dev/null)
[ -n "${JOB_ID}" ] || { echo "JOB_ID_MISSING"; exit 1; }
STDOUT=${LANDING}/logs/tm01_a800_no_pytest_${JOB_ID}.out
STDERR=${LANDING}/logs/tm01_a800_no_pytest_${JOB_ID}.err
RESULT_ROOT=${LANDING}/results/TM01_reconstructed_base_sign_aware_merge_screen_20260826
COMPACT=${LANDING}/tm01_compact_results.tar.gz

echo "=== TM01 A800 PROGRESS ==="
date -Is
echo "job_id=${JOB_ID}"
squeue -j "${JOB_ID}" -o '%.18i %.22j %.10T %.12M %.20R' 2>&1 || true
sacct -j "${JOB_ID}" -X --format=JobID%12,JobName%22,Partition%10,NodeList%10,State%14,ExitCode%8,Elapsed%10,Start%20,End%20 2>&1 || true

echo "=== PROGRESS COUNTS ==="
if [ -d "${RESULT_ROOT}" ]; then
    echo "evaluation_logs=$(find "${RESULT_ROOT}/logs" -type f -name '*.log' 2>/dev/null | wc -l)"
    echo "prediction_artifacts=$(find "${RESULT_ROOT}/runs" -type f -name 'test_results.p' 2>/dev/null | wc -l)"
    echo "saved_checkpoints=$(find "${RESULT_ROOT}/runs" -type f -name 'model_epoch030.pt' 2>/dev/null | wc -l)"
    find "${RESULT_ROOT}/logs" -type f -name '*.log' -printf '%P size=%s mtime=%TY-%Tm-%TdT%TH:%TM:%TS\n' 2>/dev/null | sort || true
    LATEST_LOG=$(find "${RESULT_ROOT}/logs" -type f -name '*.log' -printf '%T@ %p\n' 2>/dev/null | sort -n | sed -n '$s/^[^ ]* //p')
    if [ -n "${LATEST_LOG}" ]; then
        echo "=== LATEST EVALUATION LOG TAIL ==="
        echo "latest_log=${LATEST_LOG}"
        tail -n 40 "${LATEST_LOG}" || true
    fi
else
    echo "RESULT_ROOT_ABSENT"
fi

for path in "${STDOUT}" "${STDERR}" "${COMPACT}"; do
    if [ -f "${path}" ]; then stat -c '%n size=%s mtime=%y' "${path}"; else echo "ABSENT ${path}"; fi
done
if [ -s "${STDERR}" ]; then echo "=== STDERR TAIL ==="; tail -n 80 "${STDERR}" || true; fi

if [ -f "${RESULT_ROOT}/analysis/decision.json" ]; then
    echo "=== DECISION ==="
    sed -n '1,180p' "${RESULT_ROOT}/analysis/decision.json"
    echo "=== PAIRED COMPARISONS ==="
    sed -n '1,20p' "${RESULT_ROOT}/analysis/paired_comparisons.csv"
    echo "=== METHOD SUMMARY ==="
    sed -n '1,20p' "${RESULT_ROOT}/analysis/method_summary.csv"
fi
if [ -f "${RESULT_ROOT}/protocol/execution_manifest.json" ]; then
    echo "=== EXECUTION MANIFEST GUARDS ==="
    grep -E '"status"|"sealed_period_opened"|"base_provenance"|"gpu"' "${RESULT_ROOT}/protocol/execution_manifest.json" | sed -n '1,30p'
fi
echo "=== TM01 A800 PROGRESS COMPLETE ==="
exit 0
