#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL_ROOT="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels"
SEQUENCE_FILE="${CHANNEL_ROOT}/seq"
RESULT_FILE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_91.txt"
CONTROLLER="${CHANNEL_ROOT}/seq91_a39_submit_formal_evaluation_eval3.sh"
STATIC_CHECK="${CHANNEL_ROOT}/seq91_a39_submit_formal_evaluation_static_check.py"

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
[[ "$(tr -d '[:space:]' < "${SEQUENCE_FILE}")" == "91" ]] || {
  echo "channel sequence differs from 91" >&2
  exit 83
}
[[ ! -e "${RESULT_FILE}" && ! -L "${RESULT_FILE}" ]] || {
  echo "sequence-91 result already exists" >&2
  exit 84
}
require_identity "${CONTROLLER}" "079c2353f319f05e0d3737630752a705067126e1abfa5d99b82f29fb2b5162c7" "19742" "sequence-91 controller"
require_identity "${STATIC_CHECK}" "423c7963af0e5e6dcbe2a9c8b475ee447838b261b1a52b8c339a37a93b5735a7" "4350" "sequence-91 static checker"
python -B -S "${STATIC_CHECK}"
echo "SEQ91_A39_DISPATCH_VERIFIED"
exec bash "${CONTROLLER}"
