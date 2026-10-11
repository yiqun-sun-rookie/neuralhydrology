#!/bin/bash
set -eo pipefail
task_root='/data1/home/sunyiq/us_nonnegative_repair_execution_20261010_001/execution_v1'
task_python='/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python'
task_job='240054'
date -u '+OWN_SIX_READONLY_COLLECTION_UTC=%Y-%m-%dT%H:%M:%SZ'
test "$(id -un)" = sunyiq
test "$(readlink -e "$task_root")" = "$task_root"
test ! -L "$task_root/OWN_SIX_TRAINING_JOB_ID.txt"
test -f "$task_root/OWN_SIX_TRAINING_JOB_ID.txt"
test "$(cat "$task_root/OWN_SIX_TRAINING_JOB_ID.txt")" = "$task_job"
printf 'OWN_SIX_TRAINING_JOB_ID=%s\n' "$task_job"
set +e
squeue -j "$task_job" -h -o '%i|%j|%T|%R'
printf 'OWN_SIX_SQUEUE_EXIT=%s\n' "$?"
sacct -j "$task_job" -n -P -o JobIDRaw,JobName,State,ExitCode,Elapsed,AllocCPUS,ReqTRES,AllocTRES
printf 'OWN_SIX_SACCT_EXIT=%s\n' "$?"
scontrol show job -o "$task_job"
printf 'OWN_SIX_SCONTROL_EXIT=%s\n' "$?"
set -e
test "$(readlink -e "$task_root/logs")" = "$task_root/logs"
for kind in out err; do
  log="$task_root/logs/six-$task_job.$kind"
  printf 'OWN_SIX_LOG_TAIL=%s\n' "$kind"
  if [ -f "$log" ] && [ ! -L "$log" ]; then
    tail -c 8192 "$log" | sed 's/^/OWN_SIX_LOG_LINE: /'
  else
    printf 'OWN_SIX_LOG_MISSING=%s\n' "$kind"
  fi
  printf '\n'
done
printf '%s  %s\n' 'dea4b169e175a8e153b3b3120ea375752b31f5fb814de082cf509886cbd22bc0' "$task_root/src/print_six_saved_results_receipt.py" | sha256sum -c
"$task_python" -B -X utf8 "$task_root/src/print_six_saved_results_receipt.py"
printf 'OWN_SIX_READONLY_COLLECTION_DONE\n'
