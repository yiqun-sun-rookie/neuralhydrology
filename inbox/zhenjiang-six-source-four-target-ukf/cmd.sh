#!/bin/bash
set -eo pipefail

CHANNEL="zhenjiang-six-source-four-target-ukf"
MAILBOX_ROOT="$(pwd -P)"
ARCHIVE_RELATIVE="inbox/${CHANNEL}/payload_20260902_recovery_attempt_002/zhenjiang_six_source_four_target_d32_gru_ukf_development_recovery_20260902_attempt_002.tar.gz"
ARCHIVE="${MAILBOX_ROOT}/${ARCHIVE_RELATIVE}"
EXPECTED_ARCHIVE_BYTES="67054"
EXPECTED_ARCHIVE_SHA256="0effe8bd3ca26a521993aaf288734e9839e2de5347153ab5003f67d47b5560b5"
PAYLOAD_ROOT="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260902_recovery_attempt_002_payload"
RECOVERY_ROOT="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260902_recovery_attempt_002"
SLURM="${RECOVERY_ROOT}/run/scripts/hpc/zhenjiang_six_source_four_target_d32_gru_ukf_development_recovery_v1.slurm"
CONFIRMATION="CONFIRM_ZHENJIANG_SIX_SOURCE_FOUR_TARGET_UKF_2023_TECHNICAL_RECOVERY_ATTEMPT_002_20260902"

fatal() {
  echo "[FATAL] $1"
  exit 1
}

[ -f "${ARCHIVE}" ] && [ ! -L "${ARCHIVE}" ] || fatal "recovery archive is absent"
[ "$(stat -c '%s' "${ARCHIVE}")" = "${EXPECTED_ARCHIVE_BYTES}" ] || fatal "recovery archive byte count differs"
[ "$(sha256sum "${ARCHIVE}" | awk '{print $1}')" = "${EXPECTED_ARCHIVE_SHA256}" ] || fatal "recovery archive SHA-256 differs"
[ ! -e "${PAYLOAD_ROOT}" ] || fatal "exclusive extracted payload root already exists"
[ ! -e "${RECOVERY_ROOT}" ] || fatal "exclusive recovery experiment root already exists"
mkdir "${PAYLOAD_ROOT}"
tar -xzf "${ARCHIVE}" -C "${PAYLOAD_ROOT}"
[ -f "${PAYLOAD_ROOT}/deploy_exclusive_root.sh" ] || fatal "deployment script is absent after extraction"
[ -f "${PAYLOAD_ROOT}/bundle_manifest.json" ] || fatal "bundle manifest is absent after extraction"
bash -n "${PAYLOAD_ROOT}/deploy_exclusive_root.sh" || fatal "deployment script syntax check failed"
bash -n "${PAYLOAD_ROOT}/run/scripts/hpc/zhenjiang_six_source_four_target_d32_gru_ukf_development_recovery_v1.slurm" || fatal "SLURM script syntax check failed"
bash "${PAYLOAD_ROOT}/deploy_exclusive_root.sh" "${PAYLOAD_ROOT}"
[ -d "${RECOVERY_ROOT}" ] || fatal "exclusive recovery root was not deployed"
[ -f "${SLURM}" ] || fatal "recovery SLURM script was not deployed"

submitted_at="$(date -Is)"
if ! submission_output="$(sbatch "${SLURM}" "${CONFIRMATION}")"; then
  fatal "the single scheduler submission call failed"
fi
printf '%s\n' "${submission_output}"
job_id="$(printf '%s\n' "${submission_output}" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')"
[ -n "${job_id}" ] || fatal "scheduler submission output did not contain one job identifier"
submission_record="${RECOVERY_ROOT}/jobs/development_recovery_attempt_002_submission.txt"
(umask 022; printf 'submitted_at=%s\njob_id=%s\nsubmission_output=%s\narchive_sha256=%s\n' \
  "${submitted_at}" "${job_id}" "${submission_output}" "${EXPECTED_ARCHIVE_SHA256}" > "${submission_record}")
printf 'RECOVERY_ROOT=%s\n' "${RECOVERY_ROOT}"
printf 'SUBMITTED_JOB_ID=%s\n' "${job_id}"
printf 'HELD_OUT_2024_TARGET_ACCESS_AUTHORIZED=false\n'
printf 'BOUNDARY_FUTURE_TARGET_ACCESS_AUTHORIZED=false\n'
exit 0
