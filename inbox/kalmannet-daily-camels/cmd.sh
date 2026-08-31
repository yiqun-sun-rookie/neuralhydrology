#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL_ROOT="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels"
SEQUENCE_FILE="${CHANNEL_ROOT}/seq"
RESULT_FILE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_98.txt"
PRIOR_RESULT="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_97.txt"
CONTROLLER="${CHANNEL_ROOT}/seq98_a39_submit_formal_evaluation_eval5.sh"
STATIC_CHECK="${CHANNEL_ROOT}/seq98_a39_submit_formal_evaluation_static_check.py"

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

[[ -f "${SEQUENCE_FILE}" && ! -L "${SEQUENCE_FILE}" ]] || {
  echo "channel sequence is absent or unsafe" >&2
  exit 83
}
[[ "$(tr -d '[:space:]' < "${SEQUENCE_FILE}")" == "98" ]] || {
  echo "channel sequence differs from 98" >&2
  exit 83
}
[[ ! -e "${RESULT_FILE}" && ! -L "${RESULT_FILE}" ]] || {
  echo "sequence-98 result already exists" >&2
  exit 84
}
require_identity "${PRIOR_RESULT}" "1348ab73108bfb5b3c7f9dc69aefe610c55c82d46d8ad42f91cffd168b3fb104" "23453" "sequence-97 terminal diagnostic"
require_identity "${CONTROLLER}" "c1496c38863d0ed7b71f0931750da894ec2b293560f2e8fa6b2cf09ef493c196" "30311" "sequence-98 controller"
require_identity "${STATIC_CHECK}" "e17b4e1aca7df030869da77b101d615735e4170090b52a9305ecef04bc46b2a4" "9685" "sequence-98 static checker"
python -B -S "${STATIC_CHECK}"
echo "SEQ98_A39_DISPATCH_VERIFIED"
exec bash "${CONTROLLER}"
