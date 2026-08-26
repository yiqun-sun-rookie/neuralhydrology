#!/bin/bash
set -o pipefail

JOB_ID=213139
LANDING=/data1/home/sunyiq/id18_ties_merge_20260826
LOG_ROOT=${LANDING}/logs
TARGET_STDOUT=${LOG_ROOT}/tm01_slurm_${JOB_ID}.out
TARGET_STDERR=${LOG_ROOT}/tm01_slurm_${JOB_ID}.err

echo "=== TM01 A800 SWITCH PREFLIGHT ==="
date -Is
hostname
[ -f "${LANDING}/JOB_ID.txt" ] || { echo "JOB_ID_FILE_MISSING"; exit 1; }
RECORDED_JOB_ID=$(cat "${LANDING}/JOB_ID.txt")
echo "recorded_job_id=${RECORDED_JOB_ID}"
[ "${RECORDED_JOB_ID}" = "${JOB_ID}" ] || { echo "JOB_ID_MISMATCH"; exit 2; }

BEFORE=$(scontrol show job "${JOB_ID}" -o 2>&1) || { echo "${BEFORE}"; exit 3; }
echo "BEFORE ${BEFORE}"
CURRENT_STATE=$(printf '%s\n' "${BEFORE}" | tr ' ' '\n' | sed -n 's/^JobState=//p' | sed -n '1p')
CURRENT_PARTITION=$(printf '%s\n' "${BEFORE}" | tr ' ' '\n' | sed -n 's/^Partition=//p' | sed -n '1p')
echo "current_state=${CURRENT_STATE} current_partition=${CURRENT_PARTITION}"
if [ "${CURRENT_STATE}" != "PENDING" ]; then
    echo "A800_SWITCH_SKIPPED_STATE=${CURRENT_STATE}"
    squeue -j "${JOB_ID}" -o '%.18i %.22j %.10T %.12M %.20R' 2>&1 || true
    sacct -j "${JOB_ID}" -X --format=JobID%12,JobName%22,Partition%10,NodeList%10,State%14,ExitCode%8,Elapsed%10 2>&1 || true
    exit 0
fi

echo "=== LIVE HGPU8 STATE ==="
sinfo -p hgpu8 -N -o '%.10P %.12N %.8T %.8c %.16G %.30E' 2>&1 || exit 4

mkdir -p "${LOG_ROOT}" || exit 5
scontrol update JobId="${JOB_ID}" Partition=hgpu8 StdOut="${TARGET_STDOUT}" StdErr="${TARGET_STDERR}" || exit 6

AFTER=$(scontrol show job "${JOB_ID}" -o 2>&1) || { echo "${AFTER}"; exit 7; }
echo "AFTER ${AFTER}"
UPDATED_PARTITION=$(printf '%s\n' "${AFTER}" | tr ' ' '\n' | sed -n 's/^Partition=//p' | sed -n '1p')
UPDATED_STDOUT=$(printf '%s\n' "${AFTER}" | tr ' ' '\n' | sed -n 's/^StdOut=//p' | sed -n '1p')
UPDATED_STDERR=$(printf '%s\n' "${AFTER}" | tr ' ' '\n' | sed -n 's/^StdErr=//p' | sed -n '1p')
[ "${UPDATED_PARTITION}" = "hgpu8" ] || { echo "PARTITION_UPDATE_FAILED=${UPDATED_PARTITION}"; exit 8; }
[ "${UPDATED_STDOUT}" = "${TARGET_STDOUT}" ] || { echo "STDOUT_UPDATE_FAILED=${UPDATED_STDOUT}"; exit 9; }
[ "${UPDATED_STDERR}" = "${TARGET_STDERR}" ] || { echo "STDERR_UPDATE_FAILED=${UPDATED_STDERR}"; exit 10; }

echo "=== UPDATED QUEUE STATUS ==="
squeue -j "${JOB_ID}" -o '%.18i %.22j %.10T %.12M %.20R' 2>&1 || true
echo "estimated_start=$(squeue -j "${JOB_ID}" -h --start -o '%S' 2>/dev/null || true)"
sacct -j "${JOB_ID}" -X --format=JobID%12,JobName%22,Partition%10,NodeList%10,State%14,ExitCode%8,Elapsed%10,Start%20,End%20 2>&1 || true
echo "A800_SWITCH_OK job_id=${JOB_ID} stdout=${TARGET_STDOUT} stderr=${TARGET_STDERR}"
exit 0
