#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_graice_lstmnosif_20261015_001
printf 'INSTALL_LOG
'
if [ -f "$root/logs/env_install_v002.log" ]; then stat -c '%s bytes | modified %y' "$root/logs/env_install_v002.log"; tail -n 18 "$root/logs/env_install_v002.log"; fi
printf 'TASK_PROCESSES
'
ps -eo pid,ppid,etimes,stat,args | awk -v root="$root" 'index($0,root)||index($0,"id25-graice-20261015/cmd_5.sh")'
printf 'PRIMARY_STAGED_RECEIPT
'
staged=/data1/home/sunyiq/.hpc_mailbox_staging/id25-graice-20261015/result_5.txt
if [ -f "$staged" ]; then stat -c '%s bytes | modified %y' "$staged"; cat "$staged"; else echo NO_STAGED_RECEIPT; fi
printf 'RUNTIME_READY
'
if [ -f "$root/venv/runtime_ready" ]; then echo YES; else echo NO; fi
printf 'JOB_RECORDS
'
cat "$root/job_id.txt"
cat "$root/submissions.tsv"
squeue -h -u sunyiq -n id25_graice_261015 -o '%i|%j|%T|%M|%R'
printf 'TRAINING_STATE
'
for name in status.json interface_check.json failure.json; do
 if [ -f "$root/$name" ]; then printf '
FILE=%s
' "$name"; cat "$root/$name"; fi
done
