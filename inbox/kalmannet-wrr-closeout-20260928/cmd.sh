#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
launch="$parent/remaining_original_launch_001"
jobs=$(cat "$launch/all_jobids.txt")
if ! [[ "$jobs" =~ ^[0-9]+(,[0-9]+){7}$ ]]; then echo INVALID_JOB_LIST; exit 64; fi
sacct -n -X -P -j "$jobs" -o JobID,JobName,State,ExitCode,Elapsed,NodeList
squeue -h -u sunyiq -o '%i|%j|%T|%Z|%R|%E' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}'
for model in main_seed43 main_seed44 compact_seed42 compact_seed43 compact_seed44 learned_noise hand_tuned adaptive; do
  output="$parent/plain_preflight_v1/numerical_impact/runs/${model}__original_outlet_original_states__formal_attempt01"
  echo "CASE=$model"
  for name in model_start.json completion.json failure.json; do
    if [ -f "$output/$name" ]; then echo "RECEIPT=$name"; cat "$output/$name"; fi
  done
  job=$(cat "$launch/${model}.jobid")
  for log in "$launch/logs/original-one-$job.out" "$launch/logs/original-one-$job.err"; do
    if [ -f "$log" ]; then echo "LOG=$log"; tail -n 5 "$log"; fi
  done
done
