#!/usr/bin/env bash
set -Eeuo pipefail

SEQUENCE_FILE="/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-daily-camels/seq"
SCRIPT="/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-daily-camels/seq81_a38_job215801_global_gate_diagnostic.sh"
RESULT80="/data1/home/sunyiq/hpc_mailbox/outbox/kalmannet-daily-camels/result_80.txt"
ARCHIVE79="/data1/home/sunyiq/hpc_mailbox/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_SEQ79.tar.gz"
EXPECTED_SEQUENCE="81"
EXPECTED_SCRIPT_SHA256="0525048fd3e60b4038273dbcf50c319c491dde2ea40fcf87fce11e052874ee93"
EXPECTED_SCRIPT_SIZE="7195"
EXPECTED_RESULT80_SHA256="2446ca2fab69bbdbc98c47e083f4d0a8ad6a86d1a01b684d1f0d7d95582c1589"
EXPECTED_RESULT80_SIZE="7398611"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

[[ -f "$SEQUENCE_FILE" && ! -L "$SEQUENCE_FILE" ]] || { echo "sequence 81 sequence file is absent or symbolic" >&2; exit 40; }
[[ "$(tr -d '[:space:]' < "$SEQUENCE_FILE")" == "$EXPECTED_SEQUENCE" ]] || { echo "sequence 81 sequence value differs" >&2; exit 40; }
[[ -f "$SCRIPT" && ! -L "$SCRIPT" ]] || { echo "sequence 81 diagnostic script is absent or symbolic" >&2; exit 40; }
[[ "$(sha256_file "$SCRIPT")" == "$EXPECTED_SCRIPT_SHA256" ]] || { echo "sequence 81 diagnostic script hash differs" >&2; exit 40; }
[[ "$(stat -c '%s' "$SCRIPT")" == "$EXPECTED_SCRIPT_SIZE" ]] || { echo "sequence 81 diagnostic script size differs" >&2; exit 40; }
[[ -f "$RESULT80" && ! -L "$RESULT80" ]] || { echo "sequence 80 receipt is absent or symbolic" >&2; exit 40; }
[[ "$(sha256_file "$RESULT80")" == "$EXPECTED_RESULT80_SHA256" ]] || { echo "sequence 80 receipt hash differs" >&2; exit 40; }
[[ "$(stat -c '%s' "$RESULT80")" == "$EXPECTED_RESULT80_SIZE" ]] || { echo "sequence 80 receipt size differs" >&2; exit 40; }
grep -Fxq '### channel=kalmannet-daily-camels seq=80' "$RESULT80" || { echo "sequence 80 receipt header differs" >&2; exit 40; }
grep -Fxq 'independently recomputed global training gate differs' "$RESULT80" || { echo "sequence 80 failure identity differs" >&2; exit 40; }
grep -Fxq '### exit_code=1' "$RESULT80" || { echo "sequence 80 exit code differs" >&2; exit 40; }
[[ ! -e "$ARCHIVE79" && ! -L "$ARCHIVE79" ]] || { echo "sequence 79 evidence archive unexpectedly exists" >&2; exit 40; }

printf 'SEQ81_A38_DIAGNOSTIC_DISPATCH_VERIFIED sequence=%s script_sha256=%s script_size=%s result80_sha256=%s archive79_absent=true\n' \
  "$EXPECTED_SEQUENCE" "$EXPECTED_SCRIPT_SHA256" "$EXPECTED_SCRIPT_SIZE" "$EXPECTED_RESULT80_SHA256"
exec bash "$SCRIPT"
