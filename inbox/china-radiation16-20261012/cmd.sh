#!/bin/bash
set -eo pipefail
test "$(id -un)" = sunyiq
task_root='/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/preflight_v1'
task_expected_job='241330'
test -f "$task_root/OWN_PREFLIGHT_JOB_ID.txt"
test ! -L "$task_root/OWN_PREFLIGHT_JOB_ID.txt"
task_job=$(cat "$task_root/OWN_PREFLIGHT_JOB_ID.txt")
test "$task_job" = "$task_expected_job"
printf 'OWN_PREFLIGHT_QUERY_JOB_ID=%s\n' "$task_job"
set +e
timeout 12s squeue -j "$task_job" -h -o '%i|%j|%T|%R'
task_queue_exit=$?
timeout 12s sacct -X -j "$task_job" -n -P --format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,NodeList,AllocTRES
task_accounting_exit=$?
set -e
printf 'OWN_PREFLIGHT_SQUEUE_EXIT=%s\nOWN_PREFLIGHT_SACCT_EXIT=%s\n' "$task_queue_exit" "$task_accounting_exit"
if test -f "$task_root/PREFLIGHT_RESULT.json"; then
    printf 'OWN_PREFLIGHT_SAVED_JSON_BEGIN\n'
    cat "$task_root/PREFLIGHT_RESULT.json"
    printf '\nOWN_PREFLIGHT_SAVED_JSON_END\n'
else
    printf 'OWN_PREFLIGHT_RESULT_MISSING\n'
fi
for task_suffix in out err; do
    task_log="$task_root/logs/probe-$task_job.$task_suffix"
    if test -f "$task_log"; then
        printf 'OWN_PREFLIGHT_LOG_%s_BEGIN\n' "$task_suffix"
        tail -c 16384 "$task_log"
        printf '\nOWN_PREFLIGHT_LOG_%s_END\n' "$task_suffix"
    fi
done
printf 'OWN_PREFLIGHT_READ_DONE\n'
