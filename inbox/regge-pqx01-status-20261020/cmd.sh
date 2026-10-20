#!/bin/bash
set -eo pipefail
date -u
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B /data1/home/sunyiq/regge_experiments/REGGE-PQX03-FORECAST-OBJECTIVE-FACTORIAL/20261020-v01/status.py
if test -f "$HOME/.hpc_mailbox_staging/regge-pqx03-20261020/result_3.txt"; then
  tail -n 10 "$HOME/.hpc_mailbox_staging/regge-pqx03-20261020/result_3.txt"
fi
ps -u sunyiq -o pid,ppid,etimes,stat,args | grep -E 'regge-pqx03-20261020|runner2.sh' | grep -v grep || true
