#!/bin/bash
set -eo pipefail

JOB_ID=216552
EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831"

echo "SMOKE_JOB_ID=${JOB_ID}"
echo "QUERY_TIME=$(date -Is)"
echo "=== SQUEUE ==="
squeue -j "${JOB_ID}" -o '%i|%j|%T|%P|%N|%M|%l|%R' || true

available_fields="$(sacct --helpformat)"
fields=()
for candidate in JobIDRaw JobID JobName Partition State ExitCode ElapsedRaw Elapsed Start End NodeList AllocTRES MaxRSS; do
  if printf '%s\n' "${available_fields}" | tr ' ' '\n' | grep -qx "${candidate}"; then
    fields+=("${candidate}")
  fi
done
FORMAT="$(IFS=,; echo "${fields[*]}")"
echo "=== SACCT ==="
if [ -n "${FORMAT}" ]; then
  sacct -j "${JOB_ID}" -P --format="${FORMAT}" || true
fi

echo "=== OUTPUT_EXISTENCE ==="
for SEED in 17 29 43; do
  ATTEMPT="${EVALUATION_ROOT}/smoke/ZHD32-DUKF-DEV-EVAL-S${SEED}-V1/attempt_001"
  printf 'seed=%s final=%s partial=%s\n' \
    "${SEED}" \
    "$(test -d "${ATTEMPT}" && echo true || echo false)" \
    "$(test -d "${ATTEMPT}.partial" && echo true || echo false)"
done

OUT_LOG="${EVALUATION_ROOT}/logs/smoke_${JOB_ID}.out"
ERR_LOG="${EVALUATION_ROOT}/logs/smoke_${JOB_ID}.err"
echo "=== STDOUT_TAIL ==="
if [ -f "${OUT_LOG}" ]; then tail -n 80 "${OUT_LOG}"; else echo absent; fi
echo "=== STDERR_TAIL ==="
if [ -f "${ERR_LOG}" ]; then tail -n 80 "${ERR_LOG}"; else echo absent; fi
