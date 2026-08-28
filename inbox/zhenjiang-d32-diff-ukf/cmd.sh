#!/bin/bash
set -eo pipefail

ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
JOB_FILE="${ROOT}/jobs/smoke_job_id.txt"
[ -f "${JOB_FILE}" ] || { echo "[FATAL] smoke job identity is absent"; exit 1; }
JID="$(tr -d '\r\n' < "${JOB_FILE}")"
[[ "${JID}" =~ ^[0-9]+$ ]] || { echo "[FATAL] invalid job identifier"; exit 1; }

echo "SMOKE_RERUN_JOB_ID=${JID}"
echo "=== SQUEUE ==="
squeue -j "${JID}" -h -o '%i|%P|%j|%T|%M|%l|%R' || true
echo "=== SACCT ==="
sacct -j "${JID}" -P \
  --format=JobIDRaw,JobName,Partition,State,ExitCode,ElapsedRaw,NodeList,AllocTRES,MaxRSS || true
echo "=== STDOUT_TAIL ==="
tail -n 120 "${ROOT}/logs/zhd32-dukf-smoke-${JID}.out" 2>/dev/null || true
echo "=== STDERR_TAIL ==="
tail -n 120 "${ROOT}/logs/zhd32-dukf-smoke-${JID}.err" 2>/dev/null || true
echo "=== ATTEMPT_STATE ==="
ATTEMPT="${ROOT}/runs/smoke/ZHD32-DUKF-HPC-SMOKE-V1/attempt_001"
for path in "${ATTEMPT}" "${ATTEMPT}.partial"; do
  if [ -d "${path}" ]; then
    echo "PRESENT|${path}"
    find "${path}" -maxdepth 1 -type f -printf '%s|%f\n' | sort
  else
    echo "ABSENT|${path}"
  fi
done
