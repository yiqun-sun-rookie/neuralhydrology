#!/bin/bash
set -eo pipefail
test "$(id -un)" = sunyiq
root='/data1/home/sunyiq/us_netcdf3_metadata_date_query_20261008_001'
test ! -L "$root"
test "$(readlink -e "$root")" = "$root"
test ! -L "$root/job_id.txt"
test "$(cat "$root/job_id.txt")" = '237181'
printf 'DATE_ROOT=%s\nDATE_JOB_ID=237181\n' "$root"
printf 'ACCOUNTING_BEGIN\n'
timeout --signal=KILL 10 sacct -n -P -j '237181' --starttime=2026-10-07 --format=JobID,State,ExitCode,ElapsedRaw,AllocCPUS,MaxRSS,NodeList | head -c 3000
printf '\nACCOUNTING_END\n'
summary="$root/results/CLASSIC_DATE_SCHEMA_v1.json"
if test -f "$summary"; then
  test ! -L "$root/results"
  test ! -L "$summary"
  test "$(readlink -e "$summary")" = "$summary"
  test "$(stat -c %h "$summary")" = 1
  test "$(stat -c %s "$summary")" -le 16777216
  h=$(sha256sum "$summary")
  printf 'DATE_REPORT_SHA256=%s\nDATE_REPORT_GZIP_BASE64_BEGIN\n' "${h%% *}"
  gzip -n -c "$summary" | base64 -w 76
  printf 'DATE_REPORT_GZIP_BASE64_END\n'
  test "$(sha256sum "$summary")" = "$h"
else
  printf 'DATE_REPORT_NOT_PRESENT\n'
fi
err="$root/logs/date_237181.err"
if test -f "$err"; then
  test ! -L "$root/logs"
  test ! -L "$err"
  test "$(readlink -e "$err")" = "$err"
  printf 'OWN_ERROR_LOG_BEGIN\n'
  head -c 5000 "$err"
  printf '\nOWN_ERROR_LOG_END\n'
fi
printf 'DATE_COLLECTION_COMPLETE\n'
