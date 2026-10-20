#!/bin/bash
set -eo pipefail
date -u
hostname
uptime
ps -u sunyiq -o pid,ppid,etimes,stat,comm
for path in "$HOME/.hpc_mailbox_staging/regge-pqx01-20261020/result_2.txt" "$HOME/hpc_mailbox/outbox/regge-pqx01-20261020/result_2.txt"; do
    if [ -f "$path" ]; then
        printf 'OWN_RESULT %s\n' "$path"
        tail -n 25 "$path"
    fi
done
for path in /data1/home/sunyiq/regge_experiments/REGGE-PQX01-FROZEN-QE-CROSSBANK/20261020-v01-transfer/transfer_public.pem /data1/home/sunyiq/regge_experiments/REGGE-PQX01-FROZEN-QE-CROSSBANK/20261020-v01-transfer/transfer_private.pem; do
    if [ -f "$path" ]; then
        ls -l "$path"
    else
        printf 'ABSENT %s\n' "$path"
    fi
done
cd "$HOME/hpc_mailbox"
git rev-parse HEAD
git show HEAD:inbox/regge-pqx01-20261020/seq
