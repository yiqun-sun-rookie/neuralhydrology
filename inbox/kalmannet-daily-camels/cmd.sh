#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL="kalmannet-daily-camels"
SEQUENCE_FILE="${MAILBOX_ROOT}/inbox/${CHANNEL}/seq"
CONTROLLER="${MAILBOX_ROOT}/inbox/${CHANNEL}/seq83_a39_submit_formal_evaluation.sh"
RESULT82="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_82.txt"
RESULT83="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_83.txt"
EXPECTED_SEQUENCE="83"
EXPECTED_CONTROLLER_SHA256="815fa9232b496098a6f81de06856693a95a3960289e09766a1b8f8ee9f7eaa23"
EXPECTED_CONTROLLER_SIZE="13420"
EXPECTED_RESULT82_SHA256="a16bfb72c526ff8ec15bb5940b80d4abe8aabe96ffda6bdd322ea604a4229e69"
EXPECTED_RESULT82_SIZE="7403339"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

require_identity() {
  local path="$1" expected_sha256="$2" expected_size="$3" label="$4"
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "$label is absent, non-regular, or symbolic" >&2
    exit 80
  }
  [[ "$(stat -c '%s' "$path")" == "$expected_size" ]] || {
    echo "$label size differs" >&2
    exit 81
  }
  [[ "$(sha256_file "$path")" == "$expected_sha256" ]] || {
    echo "$label SHA-256 differs" >&2
    exit 82
  }
}

[[ -f "$SEQUENCE_FILE" && ! -L "$SEQUENCE_FILE" ]] || {
  echo "sequence file is absent, non-regular, or symbolic" >&2
  exit 83
}
[[ "$(tr -d '[:space:]' < "$SEQUENCE_FILE")" == "$EXPECTED_SEQUENCE" ]] || {
  echo "sequence is not 83" >&2
  exit 83
}
require_identity "$CONTROLLER" "$EXPECTED_CONTROLLER_SHA256" "$EXPECTED_CONTROLLER_SIZE" \
  "sequence-83 controller"
require_identity "$RESULT82" "$EXPECTED_RESULT82_SHA256" "$EXPECTED_RESULT82_SIZE" \
  "sequence-82 terminal receipt"
[[ ! -e "$RESULT83" && ! -L "$RESULT83" ]] || {
  echo "result 83 already exists" >&2
  exit 84
}

printf 'SEQ83_A39_DISPATCH_VERIFIED controller_sha256=%s controller_size=%s result82_sha256=%s\n' \
  "$EXPECTED_CONTROLLER_SHA256" "$EXPECTED_CONTROLLER_SIZE" "$EXPECTED_RESULT82_SHA256"
exec bash "$CONTROLLER"
