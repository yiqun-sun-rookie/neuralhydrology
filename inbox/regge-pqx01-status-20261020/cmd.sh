#!/bin/bash
set -o pipefail
printf 'PQX03_DIAG_NONCE_20261020_1240\n'
date -u
hostname
ps -eo pid,ppid,lstart,args | awk '/[h]pc_runner_active|[r]unner2.sh/ {print}'
TARGET="$HOME/.hpc_mailbox_staging/regge-pqx03-20261020/result_1.txt"
if [ -f "$TARGET" ]; then
    tail -n 60 "$TARGET"
else
    printf 'PQX03_SEQ1_STAGING_ABSENT\n'
fi
squeue -u sunyiq -o '%.18i %.28j %.10T %.12M %.40R'
printf 'PQX03_DIAG_END\n'
