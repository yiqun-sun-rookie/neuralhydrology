#!/bin/bash
set -o pipefail

SOURCE_JOB_ID=213139
LANDING=/data1/home/sunyiq/id18_ties_merge_20260826
SOURCE_SLURM=${LANDING}/payload/code/src/lstm_fair_531/hpc/submit_tm01_sign_aware_task_vector_merge.slurm
RETRY_SLURM=${LANDING}/submit_tm01_a800_retry.slurm
RETRY_JOB_FILE=${LANDING}/A800_RETRY_JOB_ID.txt
RESULT_ROOT=${LANDING}/results/TM01_reconstructed_base_sign_aware_merge_screen_20260826
COMPACT=${LANDING}/tm01_compact_results.tar.gz

echo "=== TM01 A800 RETRY PREFLIGHT ==="
date -Is
hostname
[ -f "${SOURCE_SLURM}" ] || { echo "SOURCE_SLURM_MISSING"; exit 1; }
[ ! -e "${RESULT_ROOT}" ] || { echo "RESULT_ROOT_ALREADY_EXISTS=${RESULT_ROOT}"; exit 2; }
[ ! -e "${COMPACT}" ] || { echo "COMPACT_ALREADY_EXISTS=${COMPACT}"; exit 3; }

if [ -f "${RETRY_JOB_FILE}" ]; then
    EXISTING_JOB_ID=$(cat "${RETRY_JOB_FILE}")
    echo "A800_RETRY_ALREADY_SUBMITTED=${EXISTING_JOB_ID}"
    squeue -j "${EXISTING_JOB_ID}" -o '%.18i %.22j %.10T %.12M %.20R' 2>&1 || true
    sacct -j "${EXISTING_JOB_ID}" -X --format=JobID%12,JobName%22,Partition%10,NodeList%10,State%14,ExitCode%8,Elapsed%10 2>&1 || true
    exit 0
fi

echo "=== FAILED SOURCE JOB ==="
sacct -j "${SOURCE_JOB_ID}" -X --format=JobID%12,JobName%22,Partition%10,NodeList%10,State%14,ExitCode%8,Elapsed%10,Start%20,End%20 2>&1 || true

mkdir -p "${LANDING}/logs" || exit 4
[ ! -e "${RETRY_SLURM}" ] || { echo "RETRY_SLURM_ALREADY_EXISTS_WITHOUT_JOB_ID"; exit 5; }
cp "${SOURCE_SLURM}" "${RETRY_SLURM}" || exit 6
sed -i 's/^#SBATCH -J .*/#SBATCH -J id18_tm01_a8r/' "${RETRY_SLURM}" || exit 6
sed -i 's/^#SBATCH -p .*/#SBATCH -p hgpu8/' "${RETRY_SLURM}" || exit 6
sed -i '/^#SBATCH --exclude=/d' "${RETRY_SLURM}" || exit 6
sed -i "s|^#SBATCH -o .*|#SBATCH -o ${LANDING}/logs/tm01_a800_retry_%j.out|" "${RETRY_SLURM}" || exit 6
sed -i "s|^#SBATCH -e .*|#SBATCH -e ${LANDING}/logs/tm01_a800_retry_%j.err|" "${RETRY_SLURM}" || exit 6

grep -Fx '#SBATCH -p hgpu8' "${RETRY_SLURM}" || exit 7
grep -Fx "#SBATCH -o ${LANDING}/logs/tm01_a800_retry_%j.out" "${RETRY_SLURM}" || exit 7
grep -Fx "#SBATCH -e ${LANDING}/logs/tm01_a800_retry_%j.err" "${RETRY_SLURM}" || exit 7
if grep -Eq 'hgpu2p|hpc_mailbox/outbox' "${RETRY_SLURM}"; then
    echo "RETRY_SLURM_CONTAINS_STALE_ROUTE"
    exit 8
fi
echo "retry_slurm_sha256=$(sha256sum "${RETRY_SLURM}" | awk '{print $1}')"

SUBMIT_OUTPUT=$(sbatch "${RETRY_SLURM}" 2>&1)
echo "${SUBMIT_OUTPUT}"
RETRY_JOB_ID=$(printf '%s\n' "${SUBMIT_OUTPUT}" | awk '/^Submitted batch job [0-9]+$/ {print $4; exit}')
[ -n "${RETRY_JOB_ID}" ] || { echo "A800_RETRY_SUBMIT_FAILED"; exit 9; }
printf '%s' "${RETRY_JOB_ID}" > "${RETRY_JOB_FILE}.tmp" || exit 10
mv "${RETRY_JOB_FILE}.tmp" "${RETRY_JOB_FILE}" || exit 10
echo "A800_RETRY_JOB_ID=${RETRY_JOB_ID}"
squeue -j "${RETRY_JOB_ID}" -o '%.18i %.22j %.10T %.12M %.20R' 2>&1 || true
echo "=== TM01 A800 RETRY SUBMITTED ==="
exit 0
