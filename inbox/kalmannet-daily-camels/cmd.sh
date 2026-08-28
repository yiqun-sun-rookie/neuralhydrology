#!/usr/bin/env bash
set -Eeuo pipefail

SEQUENCE_FILE="/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-daily-camels/seq"
SCRIPT="/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-daily-camels/seq79_a38_a800_job215801_terminal_recollect.sh"
RESULT79="/data1/home/sunyiq/hpc_mailbox/outbox/kalmannet-daily-camels/result_79.txt"
DISPATCH79="/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-daily-camels/seq79_a38_dispatch_cmd.sh"
EXPECTED_SEQUENCE="80"
EXPECTED_COLLECTOR_SEQUENCE="79"
EXPECTED_SHA256="23637bdf983fc93766f16a040146ee9c7cb1bda383ef25b978f41723b56fde7a"
EXPECTED_SIZE="75864"
EXPECTED_RESULT79_SHA256="a6a5a6773c17cc0427878be1f9b820a6ee996834fef21541b8b6f722c6150cd8"
EXPECTED_RESULT79_SIZE="7397905"
EXPECTED_DISPATCH79_SHA256="d5fe79bf575659f1cbeafb11854d9670c44b59496041598cc92fcec08ccfb422"
EXPECTED_DISPATCH79_SIZE="137"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

[[ -f "$SEQUENCE_FILE" && ! -L "$SEQUENCE_FILE" ]] || { echo "sequence 80 dispatch sequence file is absent or symbolic" >&2; exit 40; }
[[ "$(tr -d '[:space:]' < "$SEQUENCE_FILE")" == "$EXPECTED_SEQUENCE" ]] || { echo "sequence 80 dispatch sequence value differs" >&2; exit 40; }
[[ -f "$SCRIPT" && ! -L "$SCRIPT" ]] || { echo "sequence 80 dispatch script is absent or symbolic" >&2; exit 40; }
ACTUAL_SHA256="$(sha256_file "$SCRIPT")"
ACTUAL_SIZE="$(stat -c '%s' "$SCRIPT")"
[[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" && "$ACTUAL_SIZE" == "$EXPECTED_SIZE" ]] || { echo "sequence 80 dispatch script identity differs" >&2; exit 40; }
[[ -f "$RESULT79" && ! -L "$RESULT79" ]] || { echo "sequence 79 wrong-dispatch receipt is absent or symbolic" >&2; exit 40; }
[[ "$(sha256_file "$RESULT79")" == "$EXPECTED_RESULT79_SHA256" && "$(stat -c '%s' "$RESULT79")" == "$EXPECTED_RESULT79_SIZE" ]] || { echo "sequence 79 wrong-dispatch receipt identity differs" >&2; exit 40; }
grep -Fxq '### channel=kalmannet-daily-camels seq=79' "$RESULT79" || { echo "sequence 79 wrong-dispatch header differs" >&2; exit 40; }
grep -Fxq 'SEQ78_A38_GPU_RESOURCE_SUMMARY_END' "$RESULT79" || { echo "sequence 79 wrong-dispatch body differs" >&2; exit 40; }
grep -Fxq 'A38 numeric cgroup memory peak is absent' "$RESULT79" || { echo "sequence 79 wrong-dispatch failure differs" >&2; exit 40; }
grep -Fxq '### exit_code=66' "$RESULT79" || { echo "sequence 79 wrong-dispatch exit code differs" >&2; exit 40; }
if grep -Eq '^SEQ79_A38_' "$RESULT79"; then
  echo "sequence 79 unexpectedly executed the intended collector" >&2
  exit 40
fi
[[ -f "$DISPATCH79" && ! -L "$DISPATCH79" ]] || { echo "sequence 79 wrong-dispatch snapshot is absent or symbolic" >&2; exit 40; }
[[ "$(sha256_file "$DISPATCH79")" == "$EXPECTED_DISPATCH79_SHA256" && "$(stat -c '%s' "$DISPATCH79")" == "$EXPECTED_DISPATCH79_SIZE" ]] || { echo "sequence 79 wrong-dispatch snapshot identity differs" >&2; exit 40; }
grep -Fxq 'exec bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-daily-camels/seq78_a38_a800_job215801_terminal_recollect.sh' "$DISPATCH79" || { echo "sequence 79 wrong-dispatch target differs" >&2; exit 40; }

printf 'SEQ80_A38_DISPATCH_VERIFIED sequence=%s collector_sequence=%s path=%s sha256=%s size=%s result79_sha256=%s dispatch79_sha256=%s\n' \
  "$EXPECTED_SEQUENCE" "$EXPECTED_COLLECTOR_SEQUENCE" "$SCRIPT" "$ACTUAL_SHA256" "$ACTUAL_SIZE" "$EXPECTED_RESULT79_SHA256" "$EXPECTED_DISPATCH79_SHA256"
exec bash "$SCRIPT"
