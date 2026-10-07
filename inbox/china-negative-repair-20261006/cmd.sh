#!/bin/bash
set -eo pipefail
test "$(id -un)" = sunyiq
root='/data1/home/sunyiq/china_us_negative_comparison_20261007_001'
test ! -L "$root"
test "$(readlink -e "$root")" = "$root"
test -f "$root/job_id.txt"
test ! -L "$root/job_id.txt"
test "$(cat "$root/job_id.txt")" = '237083'
printf 'US_STATISTICS_ROOT=%s\nUS_STATISTICS_JOB_ID=237083\n' "$root"
printf 'ACCOUNTING_BEGIN\n'
timeout --signal=KILL 10 sacct -n -P -j '237083' --starttime=2026-10-06 --format=JobID,State,ExitCode,ElapsedRaw,AllocCPUS,MaxRSS,NodeList | head -c 3000
printf '\nACCOUNTING_END\n'
summary="$root/results/US_NEGATIVE_SUMMARY_v1.json"
if test -f "$summary"; then
  test ! -L "$root/results"
  test ! -L "$summary"
  test "$(readlink -e "$summary")" = "$summary"
  test "$(stat -c %s "$summary")" -le 30000
  test "$(stat -c %h "$summary")" = 1
  h=$(sha256sum "$summary")
  printf 'SUMMARY_SHA256=%s\nSUMMARY_JSON_BEGIN\n' "${h%% *}"
  cat "$summary"
  printf 'SUMMARY_JSON_END\n'
  test "$(sha256sum "$summary")" = "$h"
  csv="$root/results/negative_by_basin_model.csv"
  if test -f "$csv"; then
    test ! -L "$csv"
    test "$(readlink -e "$csv")" = "$csv"
    test "$(stat -c %s "$csv")" -le 1500000
    printf 'BY_BASIN_CSV_BYTES=%s\n' "$(stat -c %s "$csv")"
    sha256sum "$csv"
  fi
else
  printf 'SUMMARY_NOT_PRESENT\n'
fi
err="$root/logs/statistics_237083.err"
if test -f "$err"; then
  test ! -L "$root/logs"
  test ! -L "$err"
  test "$(readlink -e "$err")" = "$err"
  printf 'OWN_ERROR_LOG_BEGIN\n'
  head -c 5000 "$err"
  printf '\nOWN_ERROR_LOG_END\n'
fi
printf 'US_STATISTICS_COLLECTION_COMPLETE\n'
