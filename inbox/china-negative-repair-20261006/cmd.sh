#!/bin/bash
set -eo pipefail
test "$(id -un)" = sunyiq
root='/data1/home/sunyiq/us_global_source_metadata_20261008_001'
test ! -L "$root"
test "$(readlink -e "$root")" = "$root"
test ! -L "$root/job_id.txt"
test "$(cat "$root/job_id.txt")" = '237182'
printf 'GLOBAL_ROOT=%s\nGLOBAL_JOB_ID=237182\n' "$root"
printf 'ACCOUNTING_BEGIN\n'
timeout --signal=KILL 10 sacct -n -P -j '237182' --starttime=2026-10-07 --format=JobID,State,ExitCode,ElapsedRaw,AllocCPUS,MaxRSS,NodeList | head -c 3000
printf '\nACCOUNTING_END\n'
summary="$root/results/GLOBAL_SOURCE_METADATA_v1.json"
if test -f "$summary"; then
  test ! -L "$root/results"
  test ! -L "$summary"
  test "$(readlink -e "$summary")" = "$summary"
  test "$(stat -c %h "$summary")" = 1
  test "$(stat -c %s "$summary")" -le 16777216
  h=$(sha256sum "$summary")
  printf 'GLOBAL_REPORT_SHA256=%s\nGLOBAL_REPORT_GZIP_BASE64_BEGIN\n' "${h%% *}"
  gzip -n -c "$summary" | base64 -w 76
  printf 'GLOBAL_REPORT_GZIP_BASE64_END\n'
  test "$(sha256sum "$summary")" = "$h"
else
  printf 'GLOBAL_REPORT_NOT_PRESENT\n'
fi
err="$root/logs/global_237182.err"
if test -f "$err"; then
  test ! -L "$root/logs"
  test ! -L "$err"
  test "$(readlink -e "$err")" = "$err"
  printf 'OWN_ERROR_LOG_BEGIN\n'
  head -c 5000 "$err"
  printf '\nOWN_ERROR_LOG_END\n'
fi
printf 'GLOBAL_COLLECTION_COMPLETE\n'
