#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL="kalmannet-daily-camels"
SCRIPT="${MAILBOX_ROOT}/inbox/${CHANNEL}/seq87_a39_job216691_status.sh"
RESULT86="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_86.txt"
RESULT87="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_87.txt"
EXPECTED_SCRIPT_SHA256="a4c4b68ad14521e973ac33ff8a52819dde69146b0a92436f5b81537d661d2fe8"
EXPECTED_SCRIPT_SIZE="509"
EXPECTED_RESULT86_SHA256="c407382fdb7cb03b9679e171bb7cb16a8656bbb6873c89a1b93ba9c26be8c7c7"
EXPECTED_RESULT86_SIZE="1193"

sha256_file() { sha256sum "$1" | awk '{print $1}'; }
require_identity() {
  local path="$1" sha="$2" size="$3" label="$4"
  [[ -f "${path}" && ! -L "${path}" ]] || { echo "${label} is absent or symbolic" >&2; exit 80; }
  [[ "$(stat -c '%s' "${path}")" == "${size}" ]] || { echo "${label} size differs" >&2; exit 81; }
  [[ "$(sha256_file "${path}")" == "${sha}" ]] || { echo "${label} SHA-256 differs" >&2; exit 82; }
}

[[ "$(tr -d '[:space:]' < "${MAILBOX_ROOT}/inbox/${CHANNEL}/seq")" == "87" ]] || {
  echo "sequence is not 87" >&2
  exit 83
}
require_identity "${SCRIPT}" "${EXPECTED_SCRIPT_SHA256}" "${EXPECTED_SCRIPT_SIZE}" "sequence-87 status query"
require_identity "${RESULT86}" "${EXPECTED_RESULT86_SHA256}" "${EXPECTED_RESULT86_SIZE}" "sequence-86 submission receipt"
grep -Fq 'job_id=216691' "${RESULT86}" || { echo "sequence-86 job identity differs" >&2; exit 84; }
[[ ! -e "${RESULT87}" && ! -L "${RESULT87}" ]] || { echo "result 87 already exists" >&2; exit 85; }
printf 'SEQ87_A39_STATUS_DISPATCH_VERIFIED job_id=216691 script_sha256=%s result86_sha256=%s\n' \
  "${EXPECTED_SCRIPT_SHA256}" "${EXPECTED_RESULT86_SHA256}"
exec bash "${SCRIPT}"
