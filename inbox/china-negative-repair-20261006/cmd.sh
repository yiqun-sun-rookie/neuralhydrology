#!/bin/bash
set -eo pipefail
root='/data1/home/sunyiq/china_us_result_identity_20261007_001'
test ! -L "$root"
test "$(readlink -e "$root")" = "$root"
test ! -L "$root/job_id.txt"
test "$(cat "$root/job_id.txt")" = '237088'
printf 'NODE_IDENTITY_ROOT=%s\nNODE_IDENTITY_JOB_ID=237088\n' "$root"
printf 'ACCOUNTING_BEGIN\n'
timeout --signal=KILL 10 sacct -n -P -j '237088' --starttime=2026-10-06 --format=JobID,State,ExitCode,ElapsedRaw,AllocCPUS,MaxRSS,NodeList | head -c 3000
printf '\nACCOUNTING_END\n'
report="$root/results/NODE_IDENTITY_v1.json"
if test -f "$report"; then
  test ! -L "$root/results"
  test ! -L "$report"
  test "$(readlink -e "$report")" = "$report"
  test "$(stat -c %s "$report")" -le 50000
  test "$(stat -c %h "$report")" = 1
  h=$(sha256sum "$report")
  printf 'REPORT_SHA256=%s\nREPORT_JSON_BEGIN\n' "${h%% *}"
  cat "$report"
  printf 'REPORT_JSON_END\n'
  test "$(sha256sum "$report")" = "$h"
fi
err="$root/logs/identity_237088.err"
if test -f "$err"; then
  test ! -L "$root/logs"
  test ! -L "$err"
  test "$(readlink -e "$err")" = "$err"
  printf 'OWN_ERROR_LOG_BEGIN\n'
  head -c 5000 "$err"
  printf '\nOWN_ERROR_LOG_END\n'
fi
printf 'NODE_IDENTITY_COLLECTION_COMPLETE\n'
