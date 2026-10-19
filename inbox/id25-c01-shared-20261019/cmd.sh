#!/bin/bash
set -u
root=/data1/home/sunyiq/id25_graice_shared_c01_20261019_001
old=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
date -Iseconds
if test -s "$root/job_id.txt"; then
    job_id=$(tr -d '\r\n' < "$root/job_id.txt")
    case "$job_id" in ''|*[!0-9]*) echo INVALID_JOB_ID; exit 1;; esac
    printf 'EXPERIMENT_JOB_ID=%s\n' "$job_id"
    timeout 30 squeue -j "$job_id" --start -o '%i|%j|%T|%R|%S'
    printf 'SQUEUE_EXIT=%s\n' "$?"
    timeout 30 sacct -S 2026-10-18 -j "$job_id" --format=JobIDRaw,JobName%32,Account,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P
    printf 'SACCT_EXIT=%s\n' "$?"
    for file in "$root/logs/train_${job_id}.out" "$root/logs/train_${job_id}.err"; do
        if test -f "$file"; then printf '\nFILE=%s\n' "$file"; tail -n 45 "$file"; fi
    done
fi
if test -f "$root/submissions.tsv"; then cat "$root/submissions.tsv"; fi
if test -f "$root/ops/id25_shared_train_runtime.py"; then
    printf '\nBEGIN_TRAINING_STATE_JSON\n'
    PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 "$old/venv/bin/python" "$root/ops/id25_shared_train_runtime.py" inspect "$root"
    printf 'STATE_READ_EXIT=%s\nEND_TRAINING_STATE_JSON\n' "$?"
fi
for file in stdout.log stderr.log; do
    if test -f "$root/output/$file"; then printf '\nFILE=output/%s\n' "$file"; tail -n 35 "$root/output/$file"; fi
done
echo QUERY_ONLY_NO_PREFLIGHT_NO_SUBMISSION
exit 0
