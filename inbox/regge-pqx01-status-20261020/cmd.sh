#!/bin/bash
set -eo pipefail
date -u
if test -f "$HOME/.hpc_mailbox_staging/regge-pqx03-20261020/result_9.txt"; then
  printf '%s\n' 'PQX03_MAIN_SEQ9_STAGING'
  tail -n 18 "$HOME/.hpc_mailbox_staging/regge-pqx03-20261020/result_9.txt"
else
  printf '%s\n' 'PQX03_MAIN_SEQ9_STAGING_ABSENT'
fi
ps -u sunyiq -o pid,ppid,etimes,stat,args | grep -E 'regge-pqx03-20261020|REGGE-PQX03-FORECAST-OBJECTIVE-FACTORIAL|runner2.sh' | grep -v grep || true
timeout 90 /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B /data1/home/sunyiq/regge_experiments/REGGE-PQX03-FORECAST-OBJECTIVE-FACTORIAL/20261020-v01/status.py
