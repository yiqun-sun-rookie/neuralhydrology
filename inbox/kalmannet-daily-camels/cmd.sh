#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
SEQUENCE_FILE="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels/seq"
SCRIPT="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels/seq82_a38_a800_job215801_terminal_recollect.sh"
COLLECTOR79="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels/seq79_a38_a800_job215801_terminal_recollect.sh"
RESULT80="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_80.txt"
RESULT81="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_81.txt"
ARCHIVE79="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_SEQ79.tar.gz"
ARCHIVE82="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_SEQ82.tar.gz"
EXPECTED_SEQUENCE="82"
EXPECTED_SCRIPT_SHA256="511e1f427fe951dc8ada3f7b05d73178af1407ed052ae60129089d5f413fc206"
EXPECTED_SCRIPT_SIZE="81514"
EXPECTED_COLLECTOR79_SHA256="23637bdf983fc93766f16a040146ee9c7cb1bda383ef25b978f41723b56fde7a"
EXPECTED_COLLECTOR79_SIZE="75864"
EXPECTED_RESULT80_SHA256="2446ca2fab69bbdbc98c47e083f4d0a8ad6a86d1a01b684d1f0d7d95582c1589"
EXPECTED_RESULT80_SIZE="7398611"
EXPECTED_RESULT81_SHA256="7c6c58590f090e722690ccdb455179e1627111bae47d472f2e340661ec760265"
EXPECTED_RESULT81_SIZE="2388"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

require_identity() {
  local path="$1" expected_sha="$2" expected_size="$3" label="$4"
  [[ -f "$path" && ! -L "$path" ]] || { echo "$label is absent or symbolic" >&2; exit 40; }
  [[ "$(sha256_file "$path")" == "$expected_sha" ]] || { echo "$label hash differs" >&2; exit 40; }
  [[ "$(stat -c '%s' "$path")" == "$expected_size" ]] || { echo "$label size differs" >&2; exit 40; }
}

[[ -f "$SEQUENCE_FILE" && ! -L "$SEQUENCE_FILE" ]] || { echo "sequence 82 sequence file is absent or symbolic" >&2; exit 40; }
[[ "$(tr -d '[:space:]' < "$SEQUENCE_FILE")" == "$EXPECTED_SEQUENCE" ]] || { echo "sequence 82 sequence value differs" >&2; exit 40; }
require_identity "$SCRIPT" "$EXPECTED_SCRIPT_SHA256" "$EXPECTED_SCRIPT_SIZE" "sequence 82 collector"
require_identity "$COLLECTOR79" "$EXPECTED_COLLECTOR79_SHA256" "$EXPECTED_COLLECTOR79_SIZE" "sequence 79 collector"
require_identity "$RESULT80" "$EXPECTED_RESULT80_SHA256" "$EXPECTED_RESULT80_SIZE" "sequence 80 receipt"
require_identity "$RESULT81" "$EXPECTED_RESULT81_SHA256" "$EXPECTED_RESULT81_SIZE" "sequence 81 receipt"
grep -Fxq 'independently recomputed global training gate differs' "$RESULT80" || { echo "sequence 80 failure differs" >&2; exit 40; }
grep -Fq '"failed_condition_names":["declared_improvement_exact"]' "$RESULT81" || { echo "sequence 81 diagnosis differs" >&2; exit 40; }
grep -Fq '"overall_improvement_difference_declared_minus_recomputed":2.2920620956767834e-10' "$RESULT81" || { echo "sequence 81 numeric diagnosis differs" >&2; exit 40; }
grep -Fxq '### exit_code=0' "$RESULT81" || { echo "sequence 81 exit code differs" >&2; exit 40; }
[[ ! -e "$ARCHIVE79" && ! -L "$ARCHIVE79" ]] || { echo "sequence 79 evidence archive unexpectedly exists" >&2; exit 40; }
[[ ! -e "$ARCHIVE82" && ! -L "$ARCHIVE82" ]] || { echo "sequence 82 evidence archive unexpectedly exists" >&2; exit 40; }

printf 'SEQ82_A38_RECOLLECT_DISPATCH_VERIFIED sequence=%s script_sha256=%s script_size=%s collector79_sha256=%s result80_sha256=%s result81_sha256=%s repair=registered_A800_epoch_zero_baseline archive82_absent=true\n' \
  "$EXPECTED_SEQUENCE" "$EXPECTED_SCRIPT_SHA256" "$EXPECTED_SCRIPT_SIZE" "$EXPECTED_COLLECTOR79_SHA256" "$EXPECTED_RESULT80_SHA256" "$EXPECTED_RESULT81_SHA256"
exec bash "$SCRIPT"
