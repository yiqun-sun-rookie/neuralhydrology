#!/usr/bin/env bash
set -eo pipefail
task_root=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
sacct -n -X -P -j 228823,228835,228839,229130,229131,229342 -o JobID,JobName,State,ExitCode,Elapsed,NodeList
echo TASK_ACTIVE_QUEUE
squeue -h -u sunyiq -o '%i|%j|%T|%Z' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}'
for task_model in main_seed43 main_seed44 compact_seed42 compact_seed43 compact_seed44 learned_noise hand_tuned adaptive; do
  task_path="$task_root/plain_preflight_v1/numerical_impact/runs/${task_model}__original_outlet_original_states__formal_attempt01"
  if [ -e "$task_path" ] || [ -L "$task_path" ]; then echo "EXISTS=$task_path"; else echo "ABSENT=$task_path"; fi
done
for task_path in "$task_root/remaining_launch_001" "$task_root/remaining_original_launch_001" "$task_root/adaptive_preflight_v1/adaptive_comparison/selection_attempt01" "$task_root/adaptive_preflight_v1/adaptive_comparison/runs/matched_fixed_test__preflight_attempt01" "$task_root/adaptive_preflight_v1/adaptive_comparison/runs/matched_selected_test__preflight_attempt01"; do
  if [ -e "$task_path" ] || [ -L "$task_path" ]; then echo "EXISTS=$task_path"; else echo "ABSENT=$task_path"; fi
done
sha256sum "$task_root/plain_preflight_v1/deployed_manifest.json" "$task_root/plain_preflight_v1/formal_input_delivery_001_original/completion.json" "$task_root/adaptive_preflight_v1/package_files.sha256"
