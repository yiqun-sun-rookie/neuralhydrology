#!/bin/bash
set -o pipefail

LANDING=/data1/home/sunyiq/id18_ties_merge_20260826
RETRY_JOB_FILE=${LANDING}/A800_RETRY_JOB_ID.txt
[ -f "${RETRY_JOB_FILE}" ] || { echo "RETRY_JOB_FILE_MISSING"; exit 1; }
JOB_ID=$(cat "${RETRY_JOB_FILE}")
STDOUT=${LANDING}/logs/tm01_a800_retry_${JOB_ID}.out
STDERR=${LANDING}/logs/tm01_a800_retry_${JOB_ID}.err
RESULT_ROOT=${LANDING}/results/TM01_reconstructed_base_sign_aware_merge_screen_20260826
COMPACT=${LANDING}/tm01_compact_results.tar.gz

echo "=== TM01 A800 RETRY STATUS ==="
date -Is
hostname
echo "retry_job_id=${JOB_ID}"
squeue -j "${JOB_ID}" -o '%.18i %.22j %.10T %.12M %.20R' 2>&1 || true
echo "estimated_start=$(squeue -j "${JOB_ID}" -h --start -o '%S' 2>/dev/null || true)"
sacct -j "${JOB_ID}" -X --format=JobID%12,JobName%22,Partition%10,NodeList%10,State%14,ExitCode%8,Elapsed%10,Start%20,End%20 2>&1 || true

echo "=== TASK-SCOPED ARTIFACTS ==="
for path in "${STDOUT}" "${STDERR}" "${COMPACT}"; do
    if [ -f "${path}" ]; then
        stat -c '%n size=%s mtime=%y' "${path}"
    else
        echo "ABSENT ${path}"
    fi
done
if [ -f "${STDOUT}" ]; then
    echo "=== STDOUT TAIL ==="
    tail -n 100 "${STDOUT}" || true
fi
if [ -s "${STDERR}" ]; then
    echo "=== STDERR TAIL ==="
    tail -n 100 "${STDERR}" || true
fi

if [ -f "${COMPACT}" ]; then
    echo "compact_sha256=$(sha256sum "${COMPACT}" | awk '{print $1}')"
fi
if [ -f "${RESULT_ROOT}/analysis/decision.json" ]; then
    echo "=== DECISION ==="
    sed -n '1,160p' "${RESULT_ROOT}/analysis/decision.json"
    echo "=== PAIRED COMPARISONS ==="
    sed -n '1,20p' "${RESULT_ROOT}/analysis/paired_comparisons.csv"
    echo "=== METHOD SUMMARY ==="
    sed -n '1,20p' "${RESULT_ROOT}/analysis/method_summary.csv"
fi
if [ -f "${RESULT_ROOT}/protocol/execution_manifest.json" ]; then
    echo "=== EXECUTION MANIFEST GUARDS ==="
    grep -E '"status"|"sealed_period_opened"|"base_provenance"|"gpu"' "${RESULT_ROOT}/protocol/execution_manifest.json" | sed -n '1,20p'
fi
echo "=== TM01 A800 RETRY STATUS COMPLETE ==="
exit 0
