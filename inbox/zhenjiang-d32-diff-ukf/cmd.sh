#!/bin/bash
set -eo pipefail

EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831_r2"
SCRIPT="${EVALUATION_ROOT}/run/scripts/hpc/zhenjiang_d32_gru_differentiable_ukf_development_evaluation_smoke_v1.slurm"
REGISTRY="${EVALUATION_ROOT}/run/docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_DEVELOPMENT_EVALUATION_REGISTRY_R2.json"
ARCHIVE="${EVALUATION_ROOT}/bundles/zhenjiang_d32_gru_differentiable_ukf_dev_eval_20260831_r2.tar.gz"
EXPECTED_SCRIPT_BYTES=11126
EXPECTED_SCRIPT_SHA="b2049cc903753861468471d87b65de65c722cc8a2fca39d17b5ccbc40b60a6b8"
EXPECTED_REGISTRY_BYTES=12662
EXPECTED_REGISTRY_SHA="446db662812f1b7bf83c095dc5f279566a7b4ddfd3e7549acdabd76ceb9cbed3"
EXPECTED_ARCHIVE_BYTES=104443
EXPECTED_ARCHIVE_SHA="b571a87fc88f20cf6654f0e48f939f5c8a28240a2370fa04984c21e0e242b1f2"

fatal() {
  echo "[FATAL] $1" >&2
  exit 1
}

verify_file() {
  local path="$1"
  local expected_bytes="$2"
  local expected_sha="$3"
  [ -f "${path}" ] || fatal "missing file: ${path}"
  [ ! -L "${path}" ] || fatal "symbolic file is forbidden: ${path}"
  [ "$(stat -c '%s' "${path}")" = "${expected_bytes}" ] || \
    fatal "byte count mismatch: ${path}"
  [ "$(sha256sum "${path}" | awk '{print $1}')" = "${expected_sha}" ] || \
    fatal "SHA-256 mismatch: ${path}"
}

[ -d "${EVALUATION_ROOT}" ] || fatal "revision-two evaluation root is absent"
[ ! -L "${EVALUATION_ROOT}" ] || fatal "revision-two evaluation root is symbolic"
[ -f "${EVALUATION_ROOT}/hpc_paths.env" ] || fatal "revision-two path contract is absent"
verify_file "${SCRIPT}" "${EXPECTED_SCRIPT_BYTES}" "${EXPECTED_SCRIPT_SHA}"
verify_file "${REGISTRY}" "${EXPECTED_REGISTRY_BYTES}" "${EXPECTED_REGISTRY_SHA}"
verify_file "${ARCHIVE}" "${EXPECTED_ARCHIVE_BYTES}" "${EXPECTED_ARCHIVE_SHA}"

grep -qx "EVALUATION_ROOT=${EVALUATION_ROOT}" "${EVALUATION_ROOT}/hpc_paths.env" || \
  fatal "revision-two evaluation root contract changed"
grep -qx "REGISTRY_SHA256=${EXPECTED_REGISTRY_SHA}" "${EVALUATION_ROOT}/hpc_paths.env" || \
  fatal "revision-two registry contract changed"

for SEED in 17 29 43; do
  ATTEMPT="${EVALUATION_ROOT}/smoke/ZHD32-DUKF-DEV-EVAL-S${SEED}-V1/attempt_001"
  [ ! -e "${ATTEMPT}" ] || fatal "revision-two smoke attempt already exists: ${ATTEMPT}"
  [ ! -e "${ATTEMPT}.partial" ] || \
    fatal "revision-two partial smoke attempt already exists: ${ATTEMPT}.partial"
done

EXISTING="$(squeue -h -u "${USER}" -n zhd32_dukf_dev_smoke -o '%i|%T|%j')"
[ -z "${EXISTING}" ] || fatal "smoke job is already queued: ${EXISTING}"

JOB_ID="$(sbatch --parsable "${SCRIPT}")"
[ -n "${JOB_ID}" ] || fatal "scheduler returned no smoke job identifier"
JOB_ID="${JOB_ID%%;*}"
echo "REVISION_TWO_SMOKE_SUBMISSION_STATUS=PASS"
echo "REVISION_TWO_SMOKE_JOB_ID=${JOB_ID}"
squeue -j "${JOB_ID}" -o '%i|%j|%T|%P|%N|%M|%l|%R'
