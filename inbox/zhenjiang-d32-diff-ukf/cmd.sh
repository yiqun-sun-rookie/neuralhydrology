#!/bin/bash
set -eo pipefail

ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
JOB_FILE="${ROOT}/jobs/formal_job_id.txt"
[ -f "${JOB_FILE}" ] || { echo "[FATAL] formal job identity is absent"; exit 1; }
JID="$(tr -d '\r\n' < "${JOB_FILE}")"
[[ "${JID}" =~ ^[0-9]+$ ]] || { echo "[FATAL] invalid formal job identifier"; exit 1; }

echo "FORMAL_ARRAY_JOB_ID=${JID}"
echo "=== SQUEUE ==="
squeue -j "${JID}" -h -o '%i|%P|%j|%T|%M|%l|%R' || true
echo "=== SACCT ==="
sacct -j "${JID}" -P \
  --format=JobIDRaw,JobName,Partition,State,ExitCode,ElapsedRaw,NodeList,AllocTRES,MaxRSS || true
echo "=== FORMAL_LOG_TAILS ==="
for path in "${ROOT}"/logs/zhd32-dukf-formal-"${JID}"_*.out; do
  [ -f "${path}" ] || continue
  echo "--- ${path} ---"
  tail -n 80 "${path}"
done
for path in "${ROOT}"/logs/zhd32-dukf-formal-"${JID}"_*.err; do
  [ -f "${path}" ] || continue
  echo "--- ${path} ---"
  tail -n 80 "${path}"
done
echo "=== FORMAL_ATTEMPTS ==="
for experiment_id in ZHD32-DUKF-S17-V1 ZHD32-DUKF-S29-V1 ZHD32-DUKF-S43-V1; do
  attempt="${ROOT}/runs/formal/${experiment_id}/attempt_001"
  partial="${attempt}.partial"
  if [ -d "${attempt}" ]; then
    echo "COMPLETE_DIRECTORY|${experiment_id}"
    find "${attempt}" -maxdepth 1 -type f -printf '%s|%f\n' | sort
  elif [ -d "${partial}" ]; then
    echo "PARTIAL_DIRECTORY|${experiment_id}"
    find "${partial}" -maxdepth 1 -type f -printf '%s|%f\n' | sort
    if [ -f "${partial}/training_history.csv" ]; then
      echo "TRAINING_HISTORY_TAIL|${experiment_id}"
      tail -n 3 "${partial}/training_history.csv"
    fi
  else
    echo "ABSENT|${experiment_id}"
  fi
done
