#!/bin/bash
set -eo pipefail

EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831"
SCRIPT="${EVALUATION_ROOT}/run/scripts/hpc/zhenjiang_d32_gru_differentiable_ukf_development_evaluation_smoke_v1.slurm"
EXPECTED_SCRIPT_SHA="60d612817ad4faa6a4f05109c046e041c71b48d2aa113f5acee0b5c8744095ee"

fatal() {
  echo "[FATAL] $1" >&2
  exit 1
}

[ -d "${EVALUATION_ROOT}" ] || fatal "evaluation root is absent"
[ -f "${SCRIPT}" ] || fatal "smoke job script is absent"
[ ! -L "${SCRIPT}" ] || fatal "smoke job script is symbolic"
[ "$(sha256sum "${SCRIPT}" | awk '{print $1}')" = "${EXPECTED_SCRIPT_SHA}" ] || \
  fatal "smoke job script identity changed"

for SEED in 17 29 43; do
  ATTEMPT="${EVALUATION_ROOT}/smoke/ZHD32-DUKF-DEV-EVAL-S${SEED}-V1/attempt_001"
  [ ! -e "${ATTEMPT}" ] || fatal "smoke attempt already exists: ${ATTEMPT}"
  [ ! -e "${ATTEMPT}.partial" ] || fatal "partial smoke attempt already exists: ${ATTEMPT}.partial"
done

EXISTING="$(squeue -h -u "${USER}" -n zhd32_dukf_dev_smoke -o '%i|%T|%j')"
[ -z "${EXISTING}" ] || fatal "smoke job is already queued: ${EXISTING}"

JOB_ID="$(sbatch --parsable "${SCRIPT}")"
[ -n "${JOB_ID}" ] || fatal "scheduler returned no smoke job identifier"
echo "SMOKE_SUBMISSION_STATUS=PASS"
echo "SMOKE_JOB_ID=${JOB_ID}"
squeue -j "${JOB_ID%%;*}" -o '%i|%j|%T|%P|%N|%M|%l'
