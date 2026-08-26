#!/bin/bash
set -o pipefail

FAILED_JOB_ID=213377
LANDING=/data1/home/sunyiq/id18_ties_merge_20260826
SOURCE_SLURM=${LANDING}/submit_tm01_a800_retry.slurm
RETRY_SLURM=${LANDING}/submit_tm01_a800_retry_no_pytest.slurm
RETRY_JOB_FILE=${LANDING}/A800_RETRY_NO_PYTEST_JOB_ID.txt
RESULT_ROOT=${LANDING}/results/TM01_reconstructed_base_sign_aware_merge_screen_20260826
COMPACT=${LANDING}/tm01_compact_results.tar.gz

echo "=== TM01 A800 NO-PYTEST RETRY PREFLIGHT ==="
date -Is
hostname
[ -f "${SOURCE_SLURM}" ] || { echo "SOURCE_RETRY_SLURM_MISSING"; exit 1; }
[ ! -e "${RESULT_ROOT}" ] || { echo "RESULT_ROOT_ALREADY_EXISTS=${RESULT_ROOT}"; exit 2; }
[ ! -e "${COMPACT}" ] || { echo "COMPACT_ALREADY_EXISTS=${COMPACT}"; exit 3; }

if [ -f "${RETRY_JOB_FILE}" ]; then
    EXISTING_JOB_ID=$(cat "${RETRY_JOB_FILE}")
    echo "A800_NO_PYTEST_ALREADY_SUBMITTED=${EXISTING_JOB_ID}"
    squeue -j "${EXISTING_JOB_ID}" -o '%.18i %.22j %.10T %.12M %.20R' 2>&1 || true
    sacct -j "${EXISTING_JOB_ID}" -X --format=JobID%12,JobName%22,Partition%10,NodeList%10,State%14,ExitCode%8,Elapsed%10 2>&1 || true
    exit 0
fi

echo "=== FAILED RETRY JOB ==="
sacct -j "${FAILED_JOB_ID}" -X --format=JobID%12,JobName%22,Partition%10,NodeList%10,State%14,ExitCode%8,Elapsed%10,Start%20,End%20 2>&1 || true

[ ! -e "${RETRY_SLURM}" ] || { echo "NO_PYTEST_SLURM_ALREADY_EXISTS_WITHOUT_JOB_ID"; exit 4; }
cp "${SOURCE_SLURM}" "${RETRY_SLURM}" || exit 5
sed -i 's/^#SBATCH -J .*/#SBATCH -J id18_tm01_a8n/' "${RETRY_SLURM}" || exit 5
sed -i "s|^#SBATCH -o .*|#SBATCH -o ${LANDING}/logs/tm01_a800_no_pytest_%j.out|" "${RETRY_SLURM}" || exit 5
sed -i "s|^#SBATCH -e .*|#SBATCH -e ${LANDING}/logs/tm01_a800_no_pytest_%j.err|" "${RETRY_SLURM}" || exit 5
sed -i '/^python -X utf8 -m pytest /,+2d' "${RETRY_SLURM}" || exit 5

grep -Fx '#SBATCH -p hgpu8' "${RETRY_SLURM}" || exit 6
grep -Fx "#SBATCH -o ${LANDING}/logs/tm01_a800_no_pytest_%j.out" "${RETRY_SLURM}" || exit 6
grep -Fx "#SBATCH -e ${LANDING}/logs/tm01_a800_no_pytest_%j.err" "${RETRY_SLURM}" || exit 6
grep -F 'python -u -X utf8 -m src.lstm_fair_531.scripts.execute_tm01_hpc_screen' "${RETRY_SLURM}" || exit 6
if grep -q 'python -X utf8 -m pytest' "${RETRY_SLURM}"; then
    echo "PYTEST_COMMAND_STILL_PRESENT"
    exit 7
fi
echo "no_pytest_slurm_sha256=$(sha256sum "${RETRY_SLURM}" | awk '{print $1}')"

SUBMIT_OUTPUT=$(sbatch "${RETRY_SLURM}" 2>&1)
echo "${SUBMIT_OUTPUT}"
RETRY_JOB_ID=$(printf '%s\n' "${SUBMIT_OUTPUT}" | awk '/^Submitted batch job [0-9]+$/ {print $4; exit}')
[ -n "${RETRY_JOB_ID}" ] || { echo "A800_NO_PYTEST_SUBMIT_FAILED"; exit 8; }
printf '%s' "${RETRY_JOB_ID}" > "${RETRY_JOB_FILE}.tmp" || exit 9
mv "${RETRY_JOB_FILE}.tmp" "${RETRY_JOB_FILE}" || exit 9
echo "A800_NO_PYTEST_JOB_ID=${RETRY_JOB_ID}"
squeue -j "${RETRY_JOB_ID}" -o '%.18i %.22j %.10T %.12M %.20R' 2>&1 || true
echo "=== TM01 A800 NO-PYTEST RETRY SUBMITTED ==="
exit 0
