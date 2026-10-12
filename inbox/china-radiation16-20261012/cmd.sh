#!/bin/bash
set -eo pipefail
task_root=/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1
task_job=241360
test "$(cat "$task_root/OWN_REQUEST_BUILD_JOB_ID.txt")" = "$task_job"
printf 'OWN_REQUEST_BUILD_QUERY_JOB_ID=%s\n' "$task_job"
set +e
timeout 12s squeue -j "$task_job" -h -o '%i|%j|%T|%R'
task_sq=$?
timeout 12s sacct -j "$task_job" --noheader --parsable2 --format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,NodeList,AllocTRES
task_sa=$?
set -e
printf 'OWN_REQUEST_BUILD_SQUEUE_EXIT=%s\nOWN_REQUEST_BUILD_SACCT_EXIT=%s\n' "$task_sq" "$task_sa"
for task_kind in out err; do
    printf 'OWN_REQUEST_BUILD_LOG_%s_BEGIN\n' "$task_kind"
    if test -f "$task_root/logs/request-$task_job.$task_kind"; then
        head -c 16384 "$task_root/logs/request-$task_job.$task_kind"
    else printf 'MISSING\n'; fi
    printf '\nOWN_REQUEST_BUILD_LOG_%s_END\n' "$task_kind"
done
if test -f "$task_root/REQUEST_BUILD_RESULT.json"; then
    printf 'OWN_REQUEST_BUILD_JSON_BEGIN\n'
    cat "$task_root/REQUEST_BUILD_RESULT.json"
    printf 'OWN_REQUEST_BUILD_JSON_END\n'
fi
if test -f "$task_root/RAW_REQUESTS.tar.gz"; then
    test "$(stat -c %s "$task_root/RAW_REQUESTS.tar.gz")" -le 4194304
    printf 'OWN_REQUEST_PACKET_SHA256='
    sha256sum "$task_root/RAW_REQUESTS.tar.gz"
    printf 'OWN_REQUEST_PACKET_BASE64_BEGIN\n'
    base64 "$task_root/RAW_REQUESTS.tar.gz"
    printf 'OWN_REQUEST_PACKET_BASE64_END\n'
fi
printf 'OWN_REQUEST_BUILD_READ_DONE\n'
