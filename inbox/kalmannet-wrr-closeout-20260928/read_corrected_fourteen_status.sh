#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
launch="$parent/corrected_launch_001"
jobs=$(cat "$launch/all_jobids.txt")
if ! [[ "$jobs" =~ ^[0-9]+(,[0-9]+){13}$ ]]; then echo INVALID_FOURTEEN_JOB_INDEX; exit 64; fi
echo CORRECTED_FOURTEEN_SCHEDULER_SNAPSHOT
sacct -n -X -P -j "$jobs" -o JobID,JobName%80,State,ExitCode,Elapsed,ReqTRES%80,Timelimit,Partition,NodeList
squeue -h -u sunyiq -o '%i|%j|%T|%Z|%R|%E' | awk -F'|' -v root="$parent" '$4 == root || index($4, root "/") == 1 {print}'
models=(main_seed43 main_seed44 compact_seed42 compact_seed43 compact_seed44 learned_noise hand_tuned)
for model in "${models[@]}"; do
 for variant in corrected_outlet_original_states corrected_outlet_corrected_states; do
  case_id="${model}__${variant}"
  directory="$parent/plain_preflight_v1/numerical_impact/runs/${case_id}__formal_attempt01"
  echo "CASE=$case_id"
  for file in running.json model_start.json completion.json failure.json metrics.json issue_statistics.npz; do
   if [ -f "$directory/$file" ]; then echo "PRESENT=$file"; fi
  done
 done
done
echo NO_MODEL_RESULTS_ACCEPTED_BY_STATUS_QUERY
