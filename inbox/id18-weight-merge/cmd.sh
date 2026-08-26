#!/bin/bash
set -o pipefail

JOB_ID=213139
LANDING=/data1/home/sunyiq/id18_ties_merge_20260826
STDOUT=/data1/home/sunyiq/hpc_mailbox/outbox/id18-weight-merge/tm01_slurm_${JOB_ID}.out
STDERR=/data1/home/sunyiq/hpc_mailbox/outbox/id18-weight-merge/tm01_slurm_${JOB_ID}.err

echo "=== TM01 JOB STATUS ==="
date -Is
hostname
[ -f "${LANDING}/JOB_ID.txt" ] || { echo "JOB_ID_FILE_MISSING"; exit 1; }
RECORDED_JOB_ID=$(cat "${LANDING}/JOB_ID.txt")
echo "recorded_job_id=${RECORDED_JOB_ID}"
[ "${RECORDED_JOB_ID}" = "${JOB_ID}" ] || { echo "JOB_ID_MISMATCH"; exit 2; }

echo "=== SQUEUE ==="
squeue -j "${JOB_ID}" -o '%.18i %.22j %.10T %.12M %.20R' 2>&1 || true
echo "estimated_start=$(squeue -j "${JOB_ID}" -h --start -o '%S' 2>/dev/null || true)"

echo "=== SACCT ==="
sacct -j "${JOB_ID}" -X --format=JobID%12,JobName%22,Partition%10,NodeList%10,State%14,ExitCode%8,Elapsed%10,Start%20,End%20 2>&1 || true

echo "=== TASK-SCOPED ARTIFACTS ==="
for path in "${STDOUT}" "${STDERR}" "${LANDING}/tm01_compact_results.tar.gz"; do
    if [ -f "${path}" ]; then
        stat -c '%n size=%s mtime=%y' "${path}"
    else
        echo "ABSENT ${path}"
    fi
done

if [ -f "${STDOUT}" ]; then
    echo "=== STDOUT TAIL ==="
    tail -n 40 "${STDOUT}" || true
fi
if [ -s "${STDERR}" ]; then
    echo "=== STDERR TAIL ==="
    tail -n 40 "${STDERR}" || true
fi
echo "=== TM01 STATUS CHECK COMPLETE ==="
exit 0
