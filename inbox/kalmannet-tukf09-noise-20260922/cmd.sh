#!/usr/bin/env bash
set -eo pipefail
root='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922'
stage="$root/control/environment_probe_v1"
date -u '+%Y-%m-%dT%H:%M:%SZ'
[ "$(readlink -f "$stage")" = "$stage" ] || exit 21
response="$stage/submission_response.txt"
[ -r "$response" ] || exit 22
job_count=$(awk '/^Submitted batch job [0-9]+$/ {n++} END {print n+0}' "$response")
[ "$job_count" -eq 1 ] || exit 23
job_id=$(awk '/^Submitted batch job [0-9]+$/ {print $4}' "$response")
printf 'REGISTERED_ENVIRONMENT_ONLY_JOB=%s\n' "$job_id"
squeue -j "$job_id" -h -o '%i|%j|%T|%P|%C|%D|%R|%Z'
sacct -j "$job_id" --noheader --parsable2 --format=JobID,JobName%25,Partition,State,ExitCode,Elapsed,AllocCPUS,TotalCPU,MaxRSS,ReqMem,AllocTRES%80,NodeList
for suffix in out err; do
    logfile="$root/logs/environment_probe_${job_id}.$suffix"
    if [ -f "$logfile" ]; then
        printf 'EXACT_LOG_FILE %s\n' "$logfile"
        sha256sum "$logfile"
        tail -c 30000 "$logfile"
    else
        printf 'LOG_NOT_CREATED %s\n' "$logfile"
    fi
done
printf 'CURRENT_USER_JOBS_READ_ONLY\n'
squeue -u sunyiq -h -o '%i|%j|%T|%P|%C|%D|%R|%Z'
printf 'ENVIRONMENT_STATUS_ONLY_NO_SUBMISSIONS_OR_JOB_MUTATIONS\n'
