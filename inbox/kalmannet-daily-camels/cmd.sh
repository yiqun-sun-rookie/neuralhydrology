#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL="kalmannet-daily-camels"
SEQUENCE_FILE="${MAILBOX_ROOT}/inbox/${CHANNEL}/seq"
SCRIPT="${MAILBOX_ROOT}/inbox/${CHANNEL}/seq84_a39_job216551_status.sh"
RESULT83="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_83.txt"
RESULT84="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_84.txt"
EXPECTED_SEQUENCE="84"
EXPECTED_SCRIPT_SHA256="e7e94dce0979efd734f2599c373d7dcad623367fc7d3ea820ce36462e5b5d320"
EXPECTED_SCRIPT_SIZE="411"
EXPECTED_RESULT83_SHA256="7e34bc7c4a13314130f291442f0dfeddb0b64d8c421c8fbb157fa0dad97b8afd"
EXPECTED_RESULT83_SIZE="1090"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

require_identity() {
  local path="$1" expected_sha256="$2" expected_size="$3" label="$4"
  [[ -f "$path" && ! -L "$path" ]] || { echo "$label is absent or symbolic" >&2; exit 80; }
  [[ "$(stat -c '%s' "$path")" == "$expected_size" ]] || { echo "$label size differs" >&2; exit 81; }
  [[ "$(sha256_file "$path")" == "$expected_sha256" ]] || { echo "$label SHA-256 differs" >&2; exit 82; }
}

[[ "$(tr -d '[:space:]' < "$SEQUENCE_FILE")" == "$EXPECTED_SEQUENCE" ]] || {
  echo "sequence is not 84" >&2
  exit 83
}
require_identity "$SCRIPT" "$EXPECTED_SCRIPT_SHA256" "$EXPECTED_SCRIPT_SIZE" "sequence-84 status query"
require_identity "$RESULT83" "$EXPECTED_RESULT83_SHA256" "$EXPECTED_RESULT83_SIZE" "sequence-83 submission receipt"
[[ ! -e "$RESULT84" && ! -L "$RESULT84" ]] || { echo "result 84 already exists" >&2; exit 84; }
printf 'SEQ84_A39_DISPATCH_VERIFIED job_id=216551 script_sha256=%s result83_sha256=%s\n' \
  "$EXPECTED_SCRIPT_SHA256" "$EXPECTED_RESULT83_SHA256"
exec bash "$SCRIPT"
