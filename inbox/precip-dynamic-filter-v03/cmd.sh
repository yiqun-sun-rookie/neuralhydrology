#!/usr/bin/env bash
# Read only the isolated dynamic-filter run and its exact submitted job.
set -eo pipefail
task_root="/data1/home/sunyiq/precip_dynamic_filter_20260930/run_20261001_211612_19f6cfd5"
task_job=235197
task_resolved=$(readlink -f "$task_root")
test "$task_resolved" = "$task_root"
test -f "$task_root/submission_receipt.txt"
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf 'OWN_JOB=%s\nOWN_ROOT=%s\n' "$task_job" "$task_root"
squeue -j "$task_job" -o '%.18i %.12T %.20R %.12M %.20N' || true
sacct -j "$task_job" --format=JobID,State,ExitCode,Elapsed,MaxRSS,NodeList -P || true
scontrol show job "$task_job" || true
for task_log in "$task_root/logs/pilot-$task_job.out" "$task_root/logs/pilot-$task_job.err"; do
    printf '\nLOG=%s\n' "$task_log"
    if test -f "$task_log"; then
        stat -c 'mtime=%y bytes=%s' "$task_log"
        tail -n 90 "$task_log"
    else
        echo NOT_CREATED
    fi
done
for task_record in synthetic/technical_gate.json synthetic/failure.json probe/probe_gate.json probe/failure.json pilot/failure.json pilot/complete.json pilot/selection_locked.json pilot/summary.json; do
    if test -f "$task_root/$task_record"; then
        printf '\nRECORD=%s\n' "$task_record"
        cat "$task_root/$task_record"
    fi
done
if test -d "$task_root/pilot"; then
    printf '\nEPOCH_FILE_COUNT='
    find "$task_root/pilot" -type f -name 'epoch_*.json' | wc -l
    printf 'FIT_SUMMARY_COUNT='
    find "$task_root/pilot" -type f -name 'fit_summary.json' | wc -l
    find "$task_root/pilot" -type f -name 'epoch_*.json' -printf '%T@ %p\n' | sort -n | tail -n 3 | cut -d' ' -f2- | while IFS= read -r task_epoch; do
        printf '\nRECENT_EPOCH=%s\n' "$task_epoch"
        cat "$task_epoch"
    done
fi
