#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL="kalmannet-daily-camels"
SEQUENCE_FILE="${MAILBOX_ROOT}/inbox/${CHANNEL}/seq"
SCRIPT="${MAILBOX_ROOT}/inbox/${CHANNEL}/seq85_a39_job216551_terminal_diagnostic.sh"
RESULT84="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_84.txt"
RESULT85="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_85.txt"
EXPECTED_SEQUENCE="85"
EXPECTED_SCRIPT_SHA256="b2155174500da500d3b21366585fd73290ba5b158d8b3d099c7f0ffad4d67356"
EXPECTED_SCRIPT_SIZE="2136"
EXPECTED_RESULT84_SHA256="4ceecc36882f1669462634a1ebe8b208391dd705cd59696b113536f9fa60baf3"
EXPECTED_RESULT84_SIZE="703"

sha256_file() { sha256sum "$1" | awk '{print $1}'; }
require_identity() {
  local path="$1" sha="$2" size="$3" label="$4"
  [[ -f "$path" && ! -L "$path" ]] || { echo "$label is absent or symbolic" >&2; exit 80; }
  [[ "$(stat -c '%s' "$path")" == "$size" ]] || { echo "$label size differs" >&2; exit 81; }
  [[ "$(sha256_file "$path")" == "$sha" ]] || { echo "$label hash differs" >&2; exit 82; }
}

[[ "$(tr -d '[:space:]' < "$SEQUENCE_FILE")" == "$EXPECTED_SEQUENCE" ]] || { echo "sequence is not 85" >&2; exit 83; }
require_identity "$SCRIPT" "$EXPECTED_SCRIPT_SHA256" "$EXPECTED_SCRIPT_SIZE" "sequence-85 diagnostic"
require_identity "$RESULT84" "$EXPECTED_RESULT84_SHA256" "$EXPECTED_RESULT84_SIZE" "sequence-84 terminal receipt"
grep -Fq '216551|daily-knet-a39-s83|sunyiq|hgpu8|FAILED|20:0|' "$RESULT84" || { echo "sequence-84 terminal state differs" >&2; exit 84; }
[[ ! -e "$RESULT85" && ! -L "$RESULT85" ]] || { echo "result 85 already exists" >&2; exit 85; }
printf 'SEQ85_A39_DISPATCH_VERIFIED job_id=216551 script_sha256=%s result84_sha256=%s\n' "$EXPECTED_SCRIPT_SHA256" "$EXPECTED_RESULT84_SHA256"
exec bash "$SCRIPT"
