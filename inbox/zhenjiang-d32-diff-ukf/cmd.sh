#!/bin/bash
set -eo pipefail

ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
JOB_FILE="${ROOT}/jobs/formal_job_id.txt"
[ -f "${JOB_FILE}" ] || { echo "[FATAL] formal job identity is absent"; exit 1; }
JID="$(tr -d '\r\n' < "${JOB_FILE}")"
[[ "${JID}" =~ ^[0-9]+$ ]] || { echo "[FATAL] invalid formal job identifier"; exit 1; }

echo "FORMAL_ARRAY_JOB_ID=${JID}"
echo "QUERY_TIME=$(date -Is)"
echo "SLURM_VERSION=$(sacct --version)"

available_fields="$(sacct --helpformat)"
echo "=== RELEVANT_SUPPORTED_FIELDS ==="
printf '%s\n' "${available_fields}" | tr ' ' '\n' | grep -E \
  '^(JobIDRaw|JobID|JobName|Partition|State|ExitCode|ElapsedRaw|Elapsed|Start|End|NodeList|AllocTRES|MaxRSS|TRESUsageInMax)$' || true

fields=()
for candidate in JobIDRaw JobID JobName Partition State ExitCode ElapsedRaw Elapsed Start End NodeList AllocTRES MaxRSS TRESUsageInMax; do
  if printf '%s\n' "${available_fields}" | tr ' ' '\n' | grep -qx "${candidate}"; then
    fields+=("${candidate}")
  fi
done
FORMAT="$(IFS=,; echo "${fields[*]}")"
[ -n "${FORMAT}" ] || { echo "[FATAL] no compatible accounting fields"; exit 1; }
echo "ACCOUNTING_FORMAT=${FORMAT}"

echo "=== ACTUAL_JOB_IDS_FROM_IMMUTABLE_LOGS ==="
job_ids="$(
  grep -h -oE 'job_id=[0-9]+' \
    "${ROOT}"/logs/zhd32-dukf-formal-"${JID}"_*.out \
    | cut -d= -f2 | sort -un | paste -sd, -
)"
[ -n "${job_ids}" ] || { echo "[FATAL] no formal job identifiers in logs"; exit 1; }
echo "${job_ids}"

echo "=== ACCOUNTING_BY_ARRAY_ROOT ==="
sacct -S 2026-08-28T00:00:00 -E 2026-08-30T00:00:00 \
  -j "${JID}" -P --format="${FORMAT}"

echo "=== ACCOUNTING_BY_ACTUAL_JOB_IDS ==="
sacct -S 2026-08-28T00:00:00 -E 2026-08-30T00:00:00 \
  -j "${job_ids}" -P --format="${FORMAT}"

echo "=== ACCOUNTING_BY_JOB_NAME ==="
sacct -S 2026-08-28T00:00:00 -E 2026-08-30T00:00:00 \
  --name=zhd32-dukf-formal -P --format="${FORMAT}"
