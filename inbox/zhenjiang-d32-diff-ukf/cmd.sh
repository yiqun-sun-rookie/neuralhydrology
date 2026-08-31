#!/bin/bash
set -eo pipefail

EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831_r3"
SCRIPT="${EVALUATION_ROOT}/run/scripts/hpc/zhenjiang_d32_gru_differentiable_ukf_development_evaluation_smoke_v1.slurm"
REGISTRY="${EVALUATION_ROOT}/run/docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_DEVELOPMENT_EVALUATION_REGISTRY_R3.json"
ARCHIVE="${EVALUATION_ROOT}/bundles/zhenjiang_d32_gru_differentiable_ukf_dev_eval_20260831_r3.tar.gz"
EXPECTED_SCRIPT_BYTES=11126
EXPECTED_SCRIPT_SHA="ba97e4f2c829e1c8ace4afa0739572f3351046f3a5200fdefe22c3b1cc176d80"
EXPECTED_REGISTRY_BYTES=15809
EXPECTED_REGISTRY_SHA="7ce4e50faac807bbf3557eb0befc6e05769bba263390b3a1be0a55b0097d5b04"
EXPECTED_ARCHIVE_BYTES=111275
EXPECTED_ARCHIVE_SHA="9258a4160bb435cb6bd79c60d6f7e43465a1ced6d67f4718eb367acb0596f2a1"

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

[ -d "${EVALUATION_ROOT}" ] || fatal "revision-three evaluation root is absent"
[ ! -L "${EVALUATION_ROOT}" ] || fatal "revision-three evaluation root is symbolic"
[ ! -e "${EVALUATION_ROOT}.deploy_seq28_partial" ] || \
  fatal "revision-three deployment staging root still exists"
[ -f "${EVALUATION_ROOT}/hpc_paths.env" ] || \
  fatal "revision-three path contract is absent"
verify_file "${SCRIPT}" "${EXPECTED_SCRIPT_BYTES}" "${EXPECTED_SCRIPT_SHA}"
verify_file "${REGISTRY}" "${EXPECTED_REGISTRY_BYTES}" "${EXPECTED_REGISTRY_SHA}"
verify_file "${ARCHIVE}" "${EXPECTED_ARCHIVE_BYTES}" "${EXPECTED_ARCHIVE_SHA}"

grep -qx "EVALUATION_ROOT=${EVALUATION_ROOT}" "${EVALUATION_ROOT}/hpc_paths.env" || \
  fatal "revision-three evaluation root contract changed"
grep -qx "REGISTRY_SHA256=${EXPECTED_REGISTRY_SHA}" "${EVALUATION_ROOT}/hpc_paths.env" || \
  fatal "revision-three registry contract changed"
grep -qx '#SBATCH --partition=hgpu2p' "${SCRIPT}" || \
  fatal "precheck partition changed"
grep -qx '#SBATCH --exclude=ngu002' "${SCRIPT}" || \
  fatal "precheck excluded-node contract changed"
grep -qx '#SBATCH --gres=gpu:1' "${SCRIPT}" || \
  fatal "precheck graphics-processor contract changed"
grep -qx '#SBATCH --cpus-per-task=4' "${SCRIPT}" || \
  fatal "precheck central-processing-unit contract changed"
grep -q -- '--maximum-batches 2' "${SCRIPT}" || \
  fatal "precheck two-batch limit changed"

for SEED in 17 29 43; do
  ATTEMPT="${EVALUATION_ROOT}/smoke/ZHD32-DUKF-DEV-EVAL-S${SEED}-V1/attempt_001"
  [ ! -e "${ATTEMPT}" ] || \
    fatal "revision-three precheck attempt already exists: ${ATTEMPT}"
  [ ! -e "${ATTEMPT}.partial" ] || \
    fatal "revision-three partial precheck attempt already exists: ${ATTEMPT}.partial"
done

EXISTING="$(squeue -h -u "${USER}" -n zhd32_dukf_dev_smoke -o '%i|%T|%j')"
[ -z "${EXISTING}" ] || fatal "precheck job is already queued: ${EXISTING}"

JOB_ID="$(sbatch --parsable "${SCRIPT}")"
[ -n "${JOB_ID}" ] || fatal "scheduler returned no precheck job identifier"
JOB_ID="${JOB_ID%%;*}"
echo "REVISION_THREE_PRECHECK_SUBMISSION_STATUS=PASS"
echo "REVISION_THREE_PRECHECK_JOB_ID=${JOB_ID}"
squeue -j "${JOB_ID}" -o '%i|%j|%T|%P|%N|%M|%l|%R'
scontrol show job -o "${JOB_ID}" || true
