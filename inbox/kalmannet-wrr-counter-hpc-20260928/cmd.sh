#!/usr/bin/env bash
set -o pipefail
root=/data1/home/sunyiq/kalmannet_wrr_counter_diagnosis_20260928_v1
job=228714
echo '=== SCHEDULER RECEIPT ==='
sacct -n -P -j "$job" -o JobID,JobName,State,ExitCode,Elapsed,NodeList | head -8
squeue -h -j "$job" -o '%i|%j|%T|%P|%R'
echo '=== PHASE RECEIPTS ==='
find "$root/runs" -maxdepth 2 -type f \( -name completion.json -o -name failure.json -o -name model_start.json \) -print | sort
echo '=== COMPARISON ==='
if [ -f "$root/comparison.json" ]; then grep -E '"(state|stable_plain|stable_counted|cross_different|different_bit_elements|different_numeric_elements)"' "$root/comparison.json" | sed -n '1,70p'; else echo 'COMPARISON_NOT_YET_WRITTEN'; fi
echo '=== LOG TAIL ==='
if [ -f "$root/logs/job-$job.out" ]; then tail -n 18 "$root/logs/job-$job.out"; else echo 'STDOUT_NOT_YET_WRITTEN'; fi
if [ -f "$root/logs/job-$job.err" ]; then tail -n 18 "$root/logs/job-$job.err"; else echo 'STDERR_NOT_YET_WRITTEN'; fi
