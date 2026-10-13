#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/china_input_semantics_hpc_20261013_001/execution_v1
EXPECTED=241882
test -f "$ROOT/OWN_METADATA_JOB_ID"
test "$(cat "$ROOT/OWN_METADATA_JOB_ID")" = "$EXPECTED"
printf 'OWN_METADATA_QUERY_JOB_ID=%s\n' "$EXPECTED"
date -u '+OWN_METADATA_SERVER_QUERY_UTC=%Y-%m-%dT%H:%M:%SZ'
set +e
timeout 12s squeue -h -j "$EXPECTED" -o '%i|%T|%N|%C|%M'
queue_code=$?
printf 'OWN_METADATA_SQUEUE_EXIT=%s\n' "$queue_code"
timeout 12s sacct -j "$EXPECTED" --format=JobID,State,ExitCode,Elapsed,AllocCPUS,AllocTRES,MaxRSS --parsable2 --noheader
account_code=$?
printf 'OWN_METADATA_SACCT_EXIT=%s\n' "$account_code"
set -e
for file in "$ROOT/logs/probe-$EXPECTED.out" "$ROOT/logs/probe-$EXPECTED.err"; do
  printf 'OWN_METADATA_LOG_PATH=%s\n' "$file"
  if test -f "$file"; then
    head -c 32768 "$file"
    printf '\nOWN_METADATA_LOG_BYTES=%s\n' "$(stat -c %s "$file")"
  else
    printf 'OWN_METADATA_LOG_MISSING\n'
  fi
done
REPORT="$ROOT/PROBE_RESULT.json"
if test -f "$REPORT"; then
  test ! -L "$REPORT"
  size=$(stat -c %s "$REPORT")
  test "$size" -le 131072
  printf 'OWN_METADATA_REPORT_BYTES=%s\n' "$size"
  sha256sum "$REPORT"
  printf 'OWN_METADATA_REPORT_BEGIN\n'
  cat "$REPORT"
  printf 'OWN_METADATA_REPORT_END\n'
else
  printf 'OWN_METADATA_REPORT_MISSING\n'
fi
printf 'OWN_METADATA_READ_DONE\n'
