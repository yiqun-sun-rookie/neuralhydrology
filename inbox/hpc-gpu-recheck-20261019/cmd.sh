#!/bin/bash
set -u
root=/data1/home/sunyiq/hpc_gpu_recheck_20261019_001
date -Iseconds
for node in ngu001 ngu002 ngu101 ngu103 ngu201 ngu202 ngu203; do
    printf '\nNODE=%s\n' "$node"
    timeout 25 sinfo -N -n "$node" -h -o '%N|%P|%t|%G|%C|%E'
    if test -s "$root/nodes/$node/job_id.txt"; then
        job_id=$(tr -d '\r\n' < "$root/nodes/$node/job_id.txt")
        case "$job_id" in ''|*[!0-9]*) echo INVALID_JOB_ID; continue;; esac
        timeout 25 squeue -j "$job_id" -o '%i|%j|%T|%R'
        timeout 25 sacct -X -S 2026-10-19 -j "$job_id" --format=JobIDRaw,JobName%24,State,ExitCode,Elapsed,NodeList -n -P
        for file in "$root/nodes/$node/log_${job_id}.out" "$root/nodes/$node/log_${job_id}.err"; do
            if test -f "$file"; then printf 'FILE=%s\n' "$file"; tail -n 12 "$file"; fi
        done
    fi
    if test -f "$root/nodes/$node/result.json"; then
        printf 'RESULT_JSON_NODE=%s\n' "$node"
        cat "$root/nodes/$node/result.json"
        printf '\nEND_RESULT_JSON_NODE=%s\n' "$node"
    fi
done
if test -f "$root/submissions.tsv"; then printf '\nSUBMISSIONS\n'; cat "$root/submissions.tsv"; fi
echo QUERY_ONLY_NO_NEW_TESTS_OR_NODE_CHANGES
exit 0
