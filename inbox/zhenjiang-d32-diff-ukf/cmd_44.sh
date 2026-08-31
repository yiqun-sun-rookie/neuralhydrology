#!/bin/bash
set -eo pipefail

EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831_r3"
RUN_ROOT="${EVALUATION_ROOT}/run"
REGISTRY="${RUN_ROOT}/docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_DEVELOPMENT_EVALUATION_REGISTRY_R3.json"
SUMMARY="${EVALUATION_ROOT}/summary/ZHD32-DUKF-DEV-EVAL-SUMMARY-V1/attempt_001"
AUDIT="${EVALUATION_ROOT}/audit/ZHD32-DUKF-DEV-EVAL-SUMMARY-V1/attempt_001"
JOB_SCRIPT="${EVALUATION_ROOT}/jobs/aggregate_audit_v1.slurm"
JOB_RECORD="${EVALUATION_ROOT}/jobs/aggregate_audit_job_id.txt"

echo "QUERY_TIME=$(date -Is)"
echo "=== RELEVANT_QUEUE ==="
squeue -u "${USER}" -o '%i|%j|%T|%P|%N|%M|%l|%R' |
  awk 'NR == 1 || $2 ~ /^zhd32_dukf/' || true
echo "=== CPU_PARTITIONS ==="
sinfo -p hcpu48,hcpu48y -o '%P|%a|%l|%D|%t|%N' || true
echo "=== CPU_NODES ==="
sinfo -N -p hcpu48,hcpu48y -o '%N|%P|%t|%c|%m' || true
echo "=== IMMUTABLE_INPUTS ==="
sha256sum \
  "${REGISTRY}" \
  "${RUN_ROOT}/scripts/analysis/zhenjiang_d32_gru_differentiable_ukf_development_evaluation_v1.py" \
  "${RUN_ROOT}/scripts/analysis/audit_zhenjiang_d32_gru_differentiable_ukf_development_evaluation_v1.py"
for SEED in 17 29 43; do
  ATTEMPT="${EVALUATION_ROOT}/workers/ZHD32-DUKF-DEV-EVAL-S${SEED}-V1/attempt_001"
  test -d "${ATTEMPT}"
  test ! -e "${ATTEMPT}.partial"
  sha256sum "${ATTEMPT}/completion_manifest.json"
done
echo "=== CREATE_ONLY_TARGETS ==="
for TARGET in "${SUMMARY}" "${SUMMARY}.partial" "${AUDIT}" "${AUDIT}.partial" "${JOB_SCRIPT}" "${JOB_RECORD}"; do
  if [ -e "${TARGET}" ]; then
    printf 'exists|%s\n' "${TARGET}"
  else
    printf 'absent|%s\n' "${TARGET}"
  fi
done
