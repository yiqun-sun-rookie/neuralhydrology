#!/bin/bash
set -eo pipefail
test "$(id -un)" = sunyiq
root=/data1/home/sunyiq/china_negative_repair_20261006_002
test "$(timeout 10 readlink -e "$root")" = "$root"
job_id=$(cat "$root/reports/OWN_JOB_ID.txt")
test "$job_id" = 236830
printf 'OWN_CORRECTED_JOB_STATUS_UTC='
date -u '+%Y-%m-%dT%H:%M:%SZ'
printf 'OWN_JOB_ID=%s\n' "$job_id"
timeout 10 squeue -h -j "$job_id" -o '%i|%j|%T|%M|%N' || true
timeout 15 sacct -j "$job_id" --format=JobID,JobName%40,State,ExitCode,Elapsed,MaxRSS,AllocCPUS,NodeList,Start,End --parsable2 || true
if test -f "$root/reports/FULL_SHAPE_SYNTHETIC_RESULT_v1.json"; then
    test "$(wc -c < "$root/reports/FULL_SHAPE_SYNTHETIC_RESULT_v1.json")" -le 65536
    printf 'PROBE_JSON_BEGIN\n'
    cat "$root/reports/FULL_SHAPE_SYNTHETIC_RESULT_v1.json"
    printf '\nPROBE_JSON_END\n'
else printf 'PROBE_JSON_ABSENT\n'; fi
if test -f "$root/reports/BATCH_FAILURE_STAGE.json"; then
    test "$(wc -c < "$root/reports/BATCH_FAILURE_STAGE.json")" -le 4096
    printf 'FAILURE_STAGE_JSON_BEGIN\n'
    cat "$root/reports/BATCH_FAILURE_STAGE.json"
    printf '\nFAILURE_STAGE_JSON_END\n'
fi
printf 'OWN_STDOUT_TAIL_BEGIN\n'
if test -f "$root/logs/probe_${job_id}.out"; then tail -n 85 "$root/logs/probe_${job_id}.out"; fi
printf 'OWN_STDOUT_TAIL_END\nOWN_STDERR_TAIL_BEGIN\n'
if test -f "$root/logs/probe_${job_id}.err"; then tail -n 50 "$root/logs/probe_${job_id}.err"; fi
printf 'OWN_STDERR_TAIL_END\nOWN_CORRECTED_JOB_STATUS_COMPLETE\n'
