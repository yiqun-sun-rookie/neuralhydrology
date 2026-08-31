#!/bin/bash
set -uo pipefail

JOB_ID=216552
EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831"

echo "QUERY_TIME=$(date -Is)"
echo "=== SQUEUE ==="
squeue -j "${JOB_ID}" -o '%i|%j|%T|%P|%N|%M|%l|%R' || true
echo "=== ESTIMATED_START ==="
squeue --start -j "${JOB_ID}" -o '%i|%S|%R' || true
echo "=== SACCT ==="
sacct -j "${JOB_ID}" -P --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList || true
echo "=== OUTPUT_EXISTENCE ==="
for SEED in 17 29 43; do
  ATTEMPT="${EVALUATION_ROOT}/smoke/ZHD32-DUKF-DEV-EVAL-S${SEED}-V1/attempt_001"
  FINAL=false
  PARTIAL=false
  test -d "${ATTEMPT}" && FINAL=true
  test -d "${ATTEMPT}.partial" && PARTIAL=true
  printf 'seed=%s final=%s partial=%s\n' "${SEED}" "${FINAL}" "${PARTIAL}"
done
echo "=== LOG_EXISTENCE_AND_TAIL ==="
for LOG_PATH in "${EVALUATION_ROOT}/logs/smoke_${JOB_ID}.out" "${EVALUATION_ROOT}/logs/smoke_${JOB_ID}.err"; do
  if test -f "${LOG_PATH}"; then
    echo "log=${LOG_PATH} exists=true size=$(wc -c < "${LOG_PATH}")"
    tail -n 20 "${LOG_PATH}" || true
  else
    echo "log=${LOG_PATH} exists=false"
  fi
done
