#!/bin/bash
set -eo pipefail
test "$(id -un)" = sunyiq
root='/data1/home/sunyiq/us_source_document_area_catalog_20261008_001'
test ! -L "$root"
test "$(readlink -e "$root")" = "$root"
test ! -L "$root/job_id.txt"
test "$(cat "$root/job_id.txt")" = '237183'
printf 'CATALOG_ROOT=%s\nCATALOG_JOB_ID=237183\n' "$root"
printf 'ACCOUNTING_BEGIN\n'
timeout --signal=KILL 10 sacct -n -P -j '237183' --starttime=2026-10-07 --format=JobID,State,ExitCode,ElapsedRaw,AllocCPUS,MaxRSS,NodeList | head -c 3000
printf '\nACCOUNTING_END\n'
summary="$root/results/SOURCE_DOCUMENT_AREA_CATALOG_v1.json"
if test -f "$summary"; then
  test ! -L "$root/results"
  test ! -L "$summary"
  test "$(readlink -e "$summary")" = "$summary"
  test "$(stat -c %h "$summary")" = 1
  test "$(stat -c %s "$summary")" -le 2097152
  h=$(sha256sum "$summary")
  printf 'CATALOG_REPORT_SHA256=%s\nCATALOG_REPORT_GZIP_BASE64_BEGIN\n' "${h%% *}"
  gzip -n -c "$summary" | base64 -w 76
  printf 'CATALOG_REPORT_GZIP_BASE64_END\n'
  test "$(sha256sum "$summary")" = "$h"
else
  printf 'CATALOG_REPORT_NOT_PRESENT\n'
fi
err="$root/logs/catalog_237183.err"
if test -f "$err"; then
  test ! -L "$root/logs"
  test ! -L "$err"
  test "$(readlink -e "$err")" = "$err"
  printf 'OWN_ERROR_LOG_BEGIN\n'
  head -c 5000 "$err"
  printf '\nOWN_ERROR_LOG_END\n'
fi
printf 'CATALOG_COLLECTION_COMPLETE\n'
