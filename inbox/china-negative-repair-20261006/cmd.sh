#!/bin/bash
set -eo pipefail
test "$(id -un)" = sunyiq
root=/data1/home/sunyiq/china_negative_repair_20261006_001
test "$(timeout 10 readlink -e "$root")" = "$root"
test "$(timeout 10 cat "$root/reports/OWN_JOB_ID.txt")" = 236823
printf 'OWN_JOB_STATUS_UTC='
date -u '+%Y-%m-%dT%H:%M:%SZ'
printf 'OWN_JOB_ID=236823\n'
timeout 15 squeue -j 236823 -h -o '%.20i %.12P %.40j %.12T %.12M %.20R' || printf 'SQUEUE_QUERY_FAILED\n'
timeout 15 sacct -j 236823 --format=JobID,JobName,State,ExitCode,Elapsed,NodeList,AllocCPUS,Start,End -P || printf 'SACCT_QUERY_FAILED\n'
printf 'PROBE_JSON_BEGIN\n'
if test -f "$root/reports/FULL_SHAPE_SYNTHETIC_RESULT_v1.json"; then
    timeout 10 head -c 65536 "$root/reports/FULL_SHAPE_SYNTHETIC_RESULT_v1.json"
else
    printf 'PROBE_JSON_PENDING\n'
fi
printf '\nPROBE_JSON_END\n'
printf 'OWN_STDOUT_TAIL_BEGIN\n'
if test -f "$root/logs/probe_236823.out"; then timeout 10 tail -n 70 "$root/logs/probe_236823.out"; fi
printf 'OWN_STDOUT_TAIL_END\n'
printf 'OWN_STDERR_TAIL_BEGIN\n'
if test -f "$root/logs/probe_236823.err"; then timeout 10 tail -n 40 "$root/logs/probe_236823.err"; fi
printf 'OWN_STDERR_TAIL_END\n'
printf 'READ_ONLY_OWN_JOB_EXPORT_COMPLETE\n'
