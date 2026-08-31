#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL="kalmannet-daily-camels"
SCRIPT="${MAILBOX_ROOT}/inbox/${CHANNEL}/seq88_a39_job216691_terminal_diagnostic.sh"
RESULT87="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_87.txt"
RESULT88="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_88.txt"
EXPECTED_SCRIPT_SHA256="e90852f6c7b8a5af4e58455bfac28db420fc3312554769c21a0952351f1f9433"
EXPECTED_SCRIPT_SIZE="3361"
EXPECTED_RESULT87_SHA256="baa644bee7427f5acf8113c79d670c0b6f17c38a6e8c1ef65c3e02bbf5a77a35"
EXPECTED_RESULT87_SIZE="686"

sha256_file() { sha256sum "$1" | awk '{print $1}'; }
require_identity() {
  local path="$1" sha="$2" size="$3" label="$4"
  [[ -f "${path}" && ! -L "${path}" ]] || { echo "${label} is absent or symbolic" >&2; exit 80; }
  [[ "$(stat -c '%s' "${path}")" == "${size}" ]] || { echo "${label} size differs" >&2; exit 81; }
  [[ "$(sha256_file "${path}")" == "${sha}" ]] || { echo "${label} SHA-256 differs" >&2; exit 82; }
}

[[ "$(tr -d '[:space:]' < "${MAILBOX_ROOT}/inbox/${CHANNEL}/seq")" == "88" ]] || {
  echo "sequence is not 88" >&2
  exit 83
}
require_identity "${SCRIPT}" "${EXPECTED_SCRIPT_SHA256}" "${EXPECTED_SCRIPT_SIZE}" "sequence-88 terminal diagnostic"
require_identity "${RESULT87}" "${EXPECTED_RESULT87_SHA256}" "${EXPECTED_RESULT87_SIZE}" "sequence-87 terminal receipt"
grep -Fq '216691|daily-knet-a39-s86|sunyiq|hgpu8|FAILED|20:0|' "${RESULT87}" || {
  echo "sequence-87 terminal state differs" >&2
  exit 84
}
[[ ! -e "${RESULT88}" && ! -L "${RESULT88}" ]] || { echo "result 88 already exists" >&2; exit 85; }
printf 'SEQ88_A39_DIAGNOSTIC_DISPATCH_VERIFIED job_id=216691 script_sha256=%s result87_sha256=%s\n' \
  "${EXPECTED_SCRIPT_SHA256}" "${EXPECTED_RESULT87_SHA256}"
exec bash "${SCRIPT}"
