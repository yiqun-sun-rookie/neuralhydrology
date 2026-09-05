#!/usr/bin/env bash
set -eo pipefail
REMOTE_ROOT="/data1/home/sunyiq/zhenjiang_five_source_five_target_single_analysis_ukf_oracle_datong_20260904_r1"
date --iso-8601=seconds
hostname
if [ ! -d "${REMOTE_ROOT}" ] || [ -L "${REMOTE_ROOT}" ]; then
  echo 'registered_new_root_absent_or_not_ordinary'
  exit 0
fi
RECEIPT="${REMOTE_ROOT}/evidence/submission/attempt_001/submission_receipt.json"
if [ -f "${RECEIPT}" ] && [ ! -L "${RECEIPT}" ]; then
  echo '=== SUBMISSION RECEIPT ==='
  cat "${RECEIPT}"
  JOB_ID="$(sed -n 's/.*"job_id": "\([0-9][0-9]*\)".*/\1/p' "${RECEIPT}")"
  [[ "${JOB_ID}" =~ ^[0-9]+$ ]] || exit 1
  echo '=== CURRENT JOB STATE ==='
  squeue -j "${JOB_ID}" -h -o '%i|%j|%T|%P|%M|%R|%Z' || true
  sacct -j "${JOB_ID}" --format=JobID,State,ExitCode,Elapsed,NodeList -P || true
  for extension in out err; do
    LOG="${REMOTE_ROOT}/logs/stage-a-${JOB_ID}.${extension}"
    if [ -f "${LOG}" ] && [ ! -L "${LOG}" ]; then
      printf '\n=== LOG %s ===\n' "${extension}"
      tail -n 100 -- "${LOG}"
    fi
  done
else
  echo 'submission_receipt_absent'
fi
echo '=== ATTEMPT EVIDENCE NAMES ONLY ==='
find "${REMOTE_ROOT}/evidence/stage_a_attempts" "${REMOTE_ROOT}/evidence/stage_a_failures" "${REMOTE_ROOT}/runs/stage_a" -maxdepth 3 -type f -printf '%P|%s bytes\n' | head -n 55
echo 'read_only_status=true data_files_opened=false sbatch_calls=0'
