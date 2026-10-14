#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/independent_v1
EXPECTED=242527
test -f "$ROOT/OWN_SOIL_JOB_ID"
test "$(cat "$ROOT/OWN_SOIL_JOB_ID")" = "$EXPECTED"
printf 'OWN_SOIL_QUERY_JOB_ID=%s\n' "$EXPECTED"
date -u '+OWN_SOIL_SERVER_QUERY_UTC=%Y-%m-%dT%H:%M:%SZ'
set +e
timeout 12s squeue -h -j "$EXPECTED" -o '%i|%T|%N|%C|%M'
printf 'OWN_SOIL_SQUEUE_EXIT=%s\n' "$?"
timeout 12s sacct -j "$EXPECTED" --format=JobID,State,ExitCode,Elapsed,AllocCPUS,AllocTRES,MaxRSS --parsable2 --noheader
printf 'OWN_SOIL_SACCT_EXIT=%s\n' "$?"
set -e
for file in "$ROOT/logs/independent-$EXPECTED.out" "$ROOT/logs/independent-$EXPECTED.err"; do
  printf 'OWN_SOIL_LOG_PATH=%s\n' "$file"
  if test -f "$file"; then
    head -c 32768 "$file"
    printf '\nOWN_SOIL_LOG_BYTES=%s\n' "$(stat -c %s "$file")"
  else
    printf 'OWN_SOIL_LOG_MISSING\n'
  fi
done
for name in INDEPENDENT_RESULT.json INDEPENDENT_FAILURE.json; do
  file="$ROOT/$name"
  printf 'OWN_SOIL_REPORT_NAME=%s\n' "$name"
  if test -f "$file"; then
    test ! -L "$file"
    size=$(stat -c %s "$file")
    test "$size" -le 131072
    printf 'OWN_SOIL_REPORT_BYTES=%s\n' "$size"
    sha256sum "$file"
    printf 'OWN_SOIL_REPORT_BEGIN\n'
    cat "$file"
    printf 'OWN_SOIL_REPORT_END\n'
  else
    printf 'OWN_SOIL_REPORT_MISSING\n'
  fi
done
printf 'OWN_SOIL_READ_DONE\n'
