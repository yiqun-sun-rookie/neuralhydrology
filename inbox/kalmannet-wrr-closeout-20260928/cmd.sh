#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
plain="$parent/plain_preflight_v1/numerical_impact/runs"
adaptive="$parent/adaptive_preflight_v1/adaptive_comparison/runs"
echo JOB_STATUS
sacct -n -X -P -j 229381,229398,229399,229400,229401,229402,229403,229404,229405,229426 -o JobID,JobName,State,ExitCode,Elapsed,NodeList
echo ACTIVE_TASK_QUEUE
squeue -h -u sunyiq -o '%i|%j|%T|%Z|%R' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}'
for model in main_seed43 main_seed44 compact_seed42 compact_seed43 compact_seed44 learned_noise hand_tuned adaptive; do
  output="$plain/${model}__original_outlet_original_states__formal_attempt01"
  echo "ORIGINAL_CASE=$model"
  for name in model_start.json completion.json failure.json historical_reproduction.json; do
    if [ -f "$output/$name" ]; then sha256sum "$output/$name"; else echo "MISSING=$output/$name"; fi
  done
done
for case_id in matched_fixed_test matched_selected_test; do
  output="$adaptive/${case_id}__formal_attempt01"
  echo "MATCHED_TEST_CASE=$case_id"
  for name in running.json completion.json failure.json metrics.json; do
    if [ -f "$output/$name" ]; then sha256sum "$output/$name"; else echo "MISSING=$output/$name"; fi
  done
done
echo RECORD_HASHES
sha256sum "$parent/adaptive_prepare_jobid.txt" "$parent/adaptive_test_formal_jobid.txt" "$parent/remaining_original_launch_001/all_jobids.txt"
