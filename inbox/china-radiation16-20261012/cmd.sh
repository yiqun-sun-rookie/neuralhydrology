#!/bin/bash
set -eo pipefail
ROOT='/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1/coordinate_diagnostic_v1'
task_job=241366
test "$(cat "$ROOT/OWN_COORDINATE_DIAGNOSTIC_JOB_ID.txt")" = "$task_job"
printf 'OWN_REQUEST_BUILD_QUERY_JOB_ID=%s\n' "$task_job"
set +e
timeout 12s squeue -j "$task_job" -h -o '%i|%j|%T|%R'
task_sq=$?
timeout 12s sacct -j "$task_job" --noheader --parsable2 --format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,NodeList,AllocTRES
task_sa=$?
set -e
printf 'OWN_SQUEUE_EXIT=%s\nOWN_SACCT_EXIT=%s\n' "$task_sq" "$task_sa"
for task_kind in out err; do
    printf 'OWN_COORDINATE_LOG_%s_BEGIN\n' "$task_kind"
    if test -f "$ROOT/logs/coordinate-$task_job.$task_kind"; then
        head -c 32768 "$ROOT/logs/coordinate-$task_job.$task_kind"
    else printf 'MISSING\n'; fi
    printf '\nOWN_COORDINATE_LOG_%s_END\n' "$task_kind"
done
if test -f "$ROOT/COORDINATE_DIAGNOSTIC_RESULT.json"; then
    test "$(stat -c %s "$ROOT/COORDINATE_DIAGNOSTIC_RESULT.json")" -le 1048576
    printf 'OWN_COORDINATE_REPORT_BEGIN\n'
    cat "$ROOT/COORDINATE_DIAGNOSTIC_RESULT.json"
    printf 'OWN_COORDINATE_REPORT_END\n'
else printf 'OWN_COORDINATE_REPORT_MISSING\n'; fi
printf 'OWN_COORDINATE_READ_DONE\n'
