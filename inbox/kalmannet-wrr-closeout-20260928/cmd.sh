#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
test "$(cat "$parent/plain_original_formal_jobid.txt")" = 229130
test "$(cat "$parent/adaptive_validation_formal_jobid.txt")" = 229131
sacct -n -P -j 229130,229131 -o JobID,JobName,State,ExitCode,Elapsed,NodeList,MaxRSS
scontrol show job 229131
for package in plain adaptive; do
  if [ "$package" = plain ]; then subtree=numerical_impact; job=229130; logroot=formal_launch_001/logs; stem=original-bridge; else subtree=adaptive_comparison; job=229131; logroot=logs; stem=adaptive-validation; fi
  root="$parent/${package}_preflight_v1"
  echo "${package}_FORMAL_MODEL_START_FILES"
  find "$root/$subtree/runs" -path '*__formal_attempt01/model_start.json' -type f -printf '%P\n' | sort
  echo "${package}_FORMAL_COMPLETION_FILES"
  find "$root/$subtree/runs" -path '*__formal_attempt01/completion.json' -type f -printf '%P\n' | sort
  echo "${package}_FORMAL_FAILURES"
  find "$root/$subtree/runs" -path '*__formal_attempt01/failure.json' -type f -exec cat {} \;
  for suffix in out err; do
    echo "${package}_${suffix}_TAIL"
    if [ -f "$root/$logroot/$stem-$job.$suffix" ]; then tail -n 50 "$root/$logroot/$stem-$job.$suffix"; fi
  done
done
first="$parent/plain_preflight_v1/numerical_impact/runs/main_seed42__original_outlet_original_states__formal_attempt01"
for name in running.json model_start.json environment.json; do
  if [ -f "$first/$name" ]; then echo "FIRST_FORMAL_$name"; cat "$first/$name"; fi
done
