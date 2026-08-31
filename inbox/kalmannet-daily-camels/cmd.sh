#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL_ROOT="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels"
SEQUENCE_FILE="${CHANNEL_ROOT}/seq"
RESULT_FILE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_95.txt"
PRIOR_RESULT="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_94.txt"
QUERY="${CHANNEL_ROOT}/seq95_a39_status_job216974.sh"

require_identity() {
  local path="$1" expected_sha="$2" expected_size="$3" label="$4"
  [[ -f "${path}" && ! -L "${path}" ]] || {
    echo "${label} is absent, non-regular, or symbolic" >&2
    exit 80
  }
  [[ "$(stat -c '%s' "${path}")" == "${expected_size}" ]] || {
    echo "${label} size differs" >&2
    exit 81
  }
  [[ "$(sha256sum "${path}" | awk '{print $1}')" == "${expected_sha}" ]] || {
    echo "${label} SHA-256 differs" >&2
    exit 82
  }
}

[[ -f "${SEQUENCE_FILE}" && ! -L "${SEQUENCE_FILE}" ]] || exit 83
[[ "$(tr -d '[:space:]' < "${SEQUENCE_FILE}")" == "95" ]] || exit 83
[[ ! -e "${RESULT_FILE}" && ! -L "${RESULT_FILE}" ]] || exit 84
require_identity "${PRIOR_RESULT}" "9e5016900324873d62f3e43601ef59b48f4002a900c4bcc57e53b82eccab6013" "1519" "sequence-94 submission result"
require_identity "${QUERY}" "d5938e4f4f7897ad6c775a39a20a1ce48b813a713f2ef93c057c94a5b78682d1" "446" "sequence-95 status query"
echo "SEQ95_A39_STATUS_DISPATCH_VERIFIED job_id=216974"
exec bash "${QUERY}"
