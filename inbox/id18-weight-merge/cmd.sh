#!/bin/bash
set -o pipefail

JOB_ID=213139
LANDING=/data1/home/sunyiq/id18_ties_merge_20260826
STDOUT=${LANDING}/logs/tm01_slurm_${JOB_ID}.out
STDERR=/data1/home/sunyiq/hpc_mailbox/outbox/id18-weight-merge/tm01_slurm_${JOB_ID}.err
COMPACT=${LANDING}/tm01_compact_results.tar.gz

echo "=== TM01 A800 STATUS ==="
date -Is
hostname
[ "$(cat "${LANDING}/JOB_ID.txt" 2>/dev/null)" = "${JOB_ID}" ] || { echo "JOB_ID_GUARD_FAILED"; exit 1; }
squeue -j "${JOB_ID}" -o '%.18i %.22j %.10T %.12M %.20R' 2>&1 || true
echo "estimated_start=$(squeue -j "${JOB_ID}" -h --start -o '%S' 2>/dev/null || true)"
sacct -j "${JOB_ID}" -X --format=JobID%12,JobName%22,Partition%10,NodeList%10,State%14,ExitCode%8,Elapsed%10,Start%20,End%20 2>&1 || true
scontrol show job "${JOB_ID}" -o 2>&1 || true

echo "=== LIVE HGPU8 STATE ==="
sinfo -p hgpu8 -N -o '%.10P %.12N %.8T %.8c %.16G %.30E' 2>&1 || true

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
    tail -n 60 "${STDOUT}" || true
fi
if [ -s "${STDERR}" ]; then
    echo "=== STDERR TAIL ==="
    tail -n 60 "${STDERR}" || true
fi
echo "=== TM01 A800 STATUS COMPLETE ==="
exit 0
