#!/bin/bash
set -eo pipefail
test "$(id -un)" = sunyiq
root='/data1/home/sunyiq/us_header_format_diagnosis_20261007_001'
test ! -L "$root"
test "$(readlink -e "$root")" = "$root"
test ! -L "$root/job_id.txt"
test "$(cat "$root/job_id.txt")" = '237151'
printf 'INPUT_HEADER_ROOT=%s\nINPUT_HEADER_JOB_ID=237151\n' "$root"
printf 'ACCOUNTING_BEGIN\n'
timeout --signal=KILL 10 sacct -n -P -j '237151' --starttime=2026-10-07 --format=JobID,State,ExitCode,ElapsedRaw,AllocCPUS,MaxRSS,NodeList | head -c 3000
printf '\nACCOUNTING_END\n'
summary="$root/results/INPUT_SOURCE_HEADERS_v1.json"
if test -f "$summary"; then
  test ! -L "$root/results"
  test ! -L "$summary"
  test "$(readlink -e "$summary")" = "$summary"
  test "$(stat -c %h "$summary")" = 1
  test "$(stat -c %s "$summary")" -le 2097152
  h=$(sha256sum "$summary")
  printf 'HEADER_REPORT_SHA256=%s\nHEADER_REPORT_GZIP_BASE64_BEGIN\n' "${h%% *}"
  gzip -n -c "$summary" | base64 -w 76
  printf 'HEADER_REPORT_GZIP_BASE64_END\n'
  test "$(sha256sum "$summary")" = "$h"
else
  printf 'HEADER_REPORT_NOT_PRESENT\n'
fi
err="$root/logs/headers_237151.err"
if test -f "$err"; then
  test ! -L "$root/logs"
  test ! -L "$err"
  test "$(readlink -e "$err")" = "$err"
  printf 'OWN_ERROR_LOG_BEGIN\n'
  head -c 5000 "$err"
  printf '\nOWN_ERROR_LOG_END\n'
fi
printf 'INPUT_HEADER_COLLECTION_COMPLETE\n'
