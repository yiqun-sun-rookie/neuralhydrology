#!/bin/bash
set -eo pipefail
task_root='/data1/home/sunyiq/us_nonnegative_repair_execution_20261010_001/common_preparation_v1'
task_python='/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python'
test "$(id -un)" = sunyiq
test "$(readlink -e "$task_root")" = "$task_root"
test -f "$task_root/OWN_COMMON_PREPARATION_JOB_ID.txt"
test ! -L "$task_root/OWN_COMMON_PREPARATION_JOB_ID.txt"
test -d "$task_root/logs"
test ! -L "$task_root/logs"
test "$(cat "$task_root/OWN_COMMON_PREPARATION_JOB_ID.txt")" = 240033
date -u '+OWN_COMMON_READONLY_COLLECTION_UTC=%Y-%m-%dT%H:%M:%SZ'
printf 'OWN_COMMON_PREPARATION_JOB_ID=240033\n'
set +e
squeue -j 240033 -h -o '%i|%j|%T|%R'
query_exit=$?
printf 'OWN_COMMON_SQUEUE_EXIT=%s\n' "$query_exit"
sacct -j 240033 -n -P -o JobIDRaw,JobName,State,ExitCode,Elapsed,AllocCPUS,ReqTRES,AllocTRES
query_exit=$?
printf 'OWN_COMMON_SACCT_EXIT=%s\n' "$query_exit"
scontrol show job 240033
query_exit=$?
printf 'OWN_COMMON_SCONTROL_EXIT=%s\n' "$query_exit"
set -e
for suffix in out err; do
  path="$task_root/logs/common-240033.$suffix"
  if [ -f "$path" ]; then
    test ! -L "$path"
    printf 'OWN_COMMON_LOG_TAIL=%s\n' "$suffix"
    tail -c 8192 "$path"
    printf '\n'
  fi
done
"$task_python" -B -X utf8 "$task_root/src/print_common_review_receipt.py"
printf 'OWN_COMMON_COLLECTION_DONE\n'
