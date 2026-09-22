#!/bin/bash
set -eo pipefail
JID=227275
LOG=/data1/home/sunyiq/id25_coarse_label_audit_20260922/slurm-227275.out
echo '=== queue ==='
squeue -j "$JID" -h -o '%i %T %R %N' 2>&1
echo '=== accounting ==='
sacct -n -P -j "$JID" -o JobID,JobName,State,ExitCode,Elapsed,NodeList 2>&1
echo '=== compute-node log ==='
if [ -f "$LOG" ]; then
  stat -c '%n %s bytes' "$LOG"
  tail -n 35 "$LOG"
else
  echo 'LOG_NOT_YET_PRESENT'
fi
