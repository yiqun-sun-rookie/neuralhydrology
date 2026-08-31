#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL_ROOT="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels"
SEQUENCE_FILE="${CHANNEL_ROOT}/seq"
RESULT_FILE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_96.txt"
PRIOR_RESULT="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_95.txt"
QUERY="${CHANNEL_ROOT}/seq96_a39_status_job216974.sh"

require_identity() {
  local path="$1" expected_sha="$2" expected_size="$3" label="$4"
  [[ -f "${path}" && ! -L "${path}" ]] || exit 80
  [[ "$(stat -c '%s' "${path}")" == "${expected_size}" ]] || exit 81
  [[ "$(sha256sum "${path}" | awk '{print $1}')" == "${expected_sha}" ]] || exit 82
}

[[ -f "${SEQUENCE_FILE}" && ! -L "${SEQUENCE_FILE}" ]] || exit 83
[[ "$(tr -d '[:space:]' < "${SEQUENCE_FILE}")" == "96" ]] || exit 83
[[ ! -e "${RESULT_FILE}" && ! -L "${RESULT_FILE}" ]] || exit 84
require_identity "${PRIOR_RESULT}" "f6ff5a13623abbe42427669b21c51ba1b1818de3fcb845414ac0c7f36a6d0d1e" "469" "sequence-95 failed query result"
grep -Fq 'sacct: error: Unknown arguments:' "${PRIOR_RESULT}" || exit 85
grep -Fq 'SEQ95_A39_STATUS_QUERY_COMPLETE job_id=216974 squeue_exit=1 sacct_exit=1' "${PRIOR_RESULT}" || exit 85
require_identity "${QUERY}" "f00664de7f46c4f0d852cb21a20eae9ae1b535534e42331d3a0029187702aac8" "443" "sequence-96 status query"
echo "SEQ96_A39_STATUS_DISPATCH_VERIFIED job_id=216974"
exec bash "${QUERY}"
