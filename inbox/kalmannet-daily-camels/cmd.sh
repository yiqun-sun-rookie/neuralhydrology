#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL_ROOT="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels"
SEQUENCE_FILE="${CHANNEL_ROOT}/seq"
RESULT_FILE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_99.txt"
PRIOR_RESULT="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_98.txt"
QUERY="${CHANNEL_ROOT}/seq99_a39_status_job217038.sh"

require_identity() {
  local path="$1" expected_sha="$2" expected_size="$3" label="$4"
  [[ -f "${path}" && ! -L "${path}" ]] || exit 80
  [[ "$(stat -c '%s' "${path}")" == "${expected_size}" ]] || exit 81
  [[ "$(sha256sum "${path}" | awk '{print $1}')" == "${expected_sha}" ]] || exit 82
}

[[ -f "${SEQUENCE_FILE}" && ! -L "${SEQUENCE_FILE}" ]] || exit 83
[[ "$(tr -d '[:space:]' < "${SEQUENCE_FILE}")" == "99" ]] || exit 83
[[ ! -e "${RESULT_FILE}" && ! -L "${RESULT_FILE}" ]] || exit 84
require_identity "${PRIOR_RESULT}" "ea086b261036970f46f418ea4dbb99b011b8c5f9418ec2b50f3ef982275e37f2" "1924" "sequence-98 submission result"
grep -Fq 'SEQ98_A39_FORMAL_EVALUATION_SUBMITTED experiment_id=DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_V1_20260831_A39 execution_id=DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_A39_A800_EVAL5_SEQ98 job_id=217038' "${PRIOR_RESULT}" || exit 85
require_identity "${QUERY}" "ed1dd54cd71a83f1545896d529c063f4099196e318ef2658a7b84c2235f12e96" "443" "sequence-99 status query"
echo "SEQ99_A39_STATUS_DISPATCH_VERIFIED job_id=217038"
exec bash "${QUERY}"
