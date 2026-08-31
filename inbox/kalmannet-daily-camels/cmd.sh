#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL_ROOT="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels"
SEQUENCE_FILE="${CHANNEL_ROOT}/seq"
RESULT_FILE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_94.txt"
PRIOR_RESULT="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_93.txt"
CONTROLLER="${CHANNEL_ROOT}/seq94_a39_submit_formal_evaluation_eval4.sh"
STATIC_CHECK="${CHANNEL_ROOT}/seq94_a39_submit_formal_evaluation_static_check.py"

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
[[ "$(tr -d '[:space:]' < "${SEQUENCE_FILE}")" == "94" ]] || {
  echo "channel sequence differs from 94" >&2
  exit 83
}
[[ ! -e "${RESULT_FILE}" && ! -L "${RESULT_FILE}" ]] || {
  echo "sequence-94 result already exists" >&2
  exit 84
}
require_identity "${PRIOR_RESULT}" "8270074aacfa7bef826cd47ada87e352a4bb44529fdefbed19dcb3b080d2d1a5" "8837" "sequence-93 terminal diagnostic"
require_identity "${CONTROLLER}" "051fe22b834399e7e22a056448309d49454461cdc4e206be4b76b4a6652bec73" "24112" "sequence-94 controller"
require_identity "${STATIC_CHECK}" "88edd934799f2ab275cfff28da79c3eb1748faace0d84800695d7fbe32a82e5d" "6862" "sequence-94 static checker"
python -B -S "${STATIC_CHECK}"
echo "SEQ94_A39_DISPATCH_VERIFIED"
exec bash "${CONTROLLER}"
