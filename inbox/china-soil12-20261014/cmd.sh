#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/runtime_recovery_v1
EXPECTED=242304
test -f "$ROOT/OWN_RUNTIME_JOB_ID"
test "$(cat "$ROOT/OWN_RUNTIME_JOB_ID")" = "$EXPECTED"
printf 'OWN_RUNTIME_QUERY_JOB_ID=%s\n' "$EXPECTED"
date -u '+OWN_RUNTIME_SERVER_QUERY_UTC=%Y-%m-%dT%H:%M:%SZ'
set +e
timeout 12s squeue -h -j "$EXPECTED" -o '%i|%T|%N|%C|%M'
printf 'OWN_RUNTIME_SQUEUE_EXIT=%s\n' "$?"
timeout 12s sacct -j "$EXPECTED" --format=JobID,State,ExitCode,Elapsed,AllocCPUS,AllocTRES,MaxRSS --parsable2 --noheader
printf 'OWN_RUNTIME_SACCT_EXIT=%s\n' "$?"
set -e
for file in "$ROOT/logs/runtime-$EXPECTED.out" "$ROOT/logs/runtime-$EXPECTED.err"; do
  printf 'OWN_RUNTIME_LOG_PATH=%s\n' "$file"
  if test -f "$file"; then
    head -c 32768 "$file"
    printf '\nOWN_RUNTIME_LOG_BYTES=%s\n' "$(stat -c %s "$file")"
  else
    printf 'OWN_RUNTIME_LOG_MISSING\n'
  fi
done
REPORT="$ROOT/RUNTIME_RECOVERY_RESULT.json"
if test -f "$REPORT"; then
  test ! -L "$REPORT"
  size=$(stat -c %s "$REPORT")
  test "$size" -le 131072
  printf 'OWN_RUNTIME_REPORT_BYTES=%s\n' "$size"
  sha256sum "$REPORT"
  printf 'OWN_RUNTIME_REPORT_BEGIN\n'
  cat "$REPORT"
  printf 'OWN_RUNTIME_REPORT_END\n'
else
  printf 'OWN_RUNTIME_REPORT_MISSING\n'
fi
printf 'OWN_RUNTIME_READ_DONE\n'
