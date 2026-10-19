#!/bin/bash
set -u
root=/data1/home/sunyiq/id25_graice_shared_probe_20261019_001
date -Iseconds
if test -s "$root/job_id.txt"; then
    job_id=$(tr -d '\r\n' < "$root/job_id.txt")
    case "$job_id" in ''|*[!0-9]*) echo INVALID_JOB_ID; exit 1;; esac
    printf 'EXPERIMENT_JOB_ID=%s\n' "$job_id"
    timeout 30 squeue -j "$job_id" --start -o '%i|%j|%T|%R|%S'
    printf 'SQUEUE_EXIT=%s\n' "$?"
    timeout 30 sacct -X -j "$job_id" --format=JobIDRaw,JobName%32,Account,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P
    printf 'SACCT_EXIT=%s\n' "$?"
    for file in "$root/logs/probe_${job_id}.out" "$root/logs/probe_${job_id}.err"; do
        if test -f "$file"; then printf '\nFILE=%s\n' "$file"; tail -n 55 "$file"; fi
    done
else
    echo NO_JOB_ID_YET
    timeout 30 squeue -h -u sunyiq -n id25_c01_probe_261019 -o '%i|%j|%T|%R'
    timeout 30 sacct -X -u sunyiq --name=id25_c01_probe_261019 -S 2026-10-18 --format=JobIDRaw,JobName%32,State,ExitCode -n -P
fi
for file in submissions.tsv sbatch_reply.txt sbatch_error.txt allocation.json probe_output/supervisor.json probe_output/gpu_preflight.json; do
    if test -f "$root/$file"; then printf '\nFILE=%s\n' "$file"; cat "$root/$file"; fi
done
for file in stdout.log stderr.log; do
    if test -f "$root/probe_output/$file"; then printf '\nFILE=probe_output/%s\n' "$file"; tail -n 55 "$root/probe_output/$file"; fi
done
echo QUERY_ONLY_NO_SUBMISSION
exit 0
