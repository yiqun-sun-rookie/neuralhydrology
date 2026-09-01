#!/usr/bin/env bash
set -euo pipefail

REMOTE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901"
FAILED_EXECUTION_ID="DAILY_CAMELS_KNET_PER_BASIN_PILOT_A800_PROBE2_SEQ3"
FAILED_DIRECTORY="${REMOTE_ROOT}/probes/${FAILED_EXECUTION_ID}"
EXECUTION_ID="DAILY_CAMELS_KNET_PER_BASIN_PILOT_A800_PROBE3_SEQ5"
PROBE_DIRECTORY="${REMOTE_ROOT}/probes/${EXECUTION_ID}"
PROBE_WRAPPER="${PROBE_DIRECTORY}/submit_a800_probe.slurm"
PROBE_REPORT="${PROBE_DIRECTORY}/probe_receipt.json"
JOB_NAME="kdpp-a800-probe-s5"

echo '=== SUBMISSION IDENTITY ==='
date --iso-8601=seconds
hostname
echo 'channel=kalmannet-daily-perbasin sequence=5 purpose=single-A800-probe-retry-with-indexed-memory-query'

if [[ ! -f "${FAILED_DIRECTORY}/submit_a800_probe.slurm" ]]; then
  echo 'sequence-3 failed wrapper is absent' >&2
  exit 30
fi
if [[ -e "${FAILED_DIRECTORY}/probe_receipt.json" ]]; then
  echo 'sequence-3 failure unexpectedly has a completed receipt' >&2
  exit 31
fi
if [[ -e "${PROBE_DIRECTORY}" ]]; then
  echo "refusing pre-existing retry directory: ${PROBE_DIRECTORY}" >&2
  exit 32
fi
if [[ "$(grep -F -c 'torch.cuda.mem_get_info(device)' "${FAILED_DIRECTORY}/submit_a800_probe.slurm")" != "1" ]]; then
  echo 'sequence-3 wrapper does not have exactly one declared compatibility defect' >&2
  exit 33
fi

ACTIVE_BEFORE="$(squeue -h -u sunyiq -o '%i|%j|%T|%N' | awk -F'|' -v name="${JOB_NAME}" '$2 == name {count++} END {print count+0}')"
HISTORICAL_BEFORE="$(sacct -u sunyiq -S 2026-09-01T00:00:00 -X --format=JobIDRaw,JobName,State -n -P | awk -F'|' -v name="${JOB_NAME}" '$2 == name {count++} END {print count+0}')"
echo "exact_job_name_active_before=${ACTIVE_BEFORE}"
echo "exact_job_name_historical_before=${HISTORICAL_BEFORE}"
if [[ "${ACTIVE_BEFORE}" != "0" || "${HISTORICAL_BEFORE}" != "0" ]]; then
  echo 'duplicate probe identity detected before submission' >&2
  exit 34
fi

mkdir -p "${PROBE_DIRECTORY}"
sed 's/torch\.cuda\.mem_get_info(device)/torch.cuda.mem_get_info(0)/' \
  "${FAILED_DIRECTORY}/submit_a800_probe.slurm" > "${PROBE_WRAPPER}"
if [[ "$(grep -F -c 'torch.cuda.mem_get_info(0)' "${PROBE_WRAPPER}")" != "1" ]] || \
   grep -F -q 'torch.cuda.mem_get_info(device)' "${PROBE_WRAPPER}"; then
  echo 'indexed memory-query repair did not apply exactly once' >&2
  exit 35
fi
chmod 700 "${PROBE_WRAPPER}"

echo '=== WRAPPER EVIDENCE ==='
sha256sum "${FAILED_DIRECTORY}/submit_a800_probe.slurm" "${PROBE_WRAPPER}"
diff -u "${FAILED_DIRECTORY}/submit_a800_probe.slurm" "${PROBE_WRAPPER}" || true

JOB_ID="$(sbatch \
  --parsable \
  --job-name="${JOB_NAME}" \
  --output="${PROBE_DIRECTORY}/slurm-%j.out" \
  --error="${PROBE_DIRECTORY}/slurm-%j.err" \
  --export="ALL,PROBE_REPORT=${PROBE_REPORT}" \
  "${PROBE_WRAPPER}")"
case "${JOB_ID}" in
  ''|*[!0-9]*) echo "invalid Slurm job identifier: ${JOB_ID}" >&2; exit 36 ;;
esac

ACTIVE_AFTER="$(squeue -h -j "${JOB_ID}" -o '%i|%j|%T|%N' | wc -l | tr -d ' ')"
EXACT_NAME_AFTER="$(squeue -h -u sunyiq -o '%i|%j|%T|%N' | awk -F'|' -v name="${JOB_NAME}" '$2 == name {count++} END {print count+0}')"
if [[ "${ACTIVE_AFTER}" != "1" || "${EXACT_NAME_AFTER}" != "1" ]]; then
  echo 'post-submission uniqueness proof failed' >&2
  exit 37
fi

RECEIPT="${PROBE_DIRECTORY}/submission_receipt.txt"
if [[ -e "${RECEIPT}" ]]; then
  echo 'refusing to replace probe submission receipt' >&2
  exit 38
fi
{
  printf 'channel=kalmannet-daily-perbasin\n'
  printf 'sequence=5\n'
  printf 'execution_id=%s\n' "${EXECUTION_ID}"
  printf 'job_name=%s\n' "${JOB_NAME}"
  printf 'job_id=%s\n' "${JOB_ID}"
  printf 'active_before=%s\n' "${ACTIVE_BEFORE}"
  printf 'historical_before=%s\n' "${HISTORICAL_BEFORE}"
  printf 'active_after=%s\n' "${ACTIVE_AFTER}"
  printf 'exact_name_after=%s\n' "${EXACT_NAME_AFTER}"
  printf 'submission_count=1\n'
  printf 'signals_sent=0\n'
} > "${RECEIPT}"

echo '=== SUBMISSION RECEIPT ==='
cat "${RECEIPT}"
echo '=== CURRENT JOB ==='
squeue -j "${JOB_ID}" -o '%i|%j|%P|%T|%R|%M|%S|%N'
echo '=== SUBMISSION COMPLETE: EXACTLY ONE PROBE, NO TRAINING OR SIGNAL ==='
