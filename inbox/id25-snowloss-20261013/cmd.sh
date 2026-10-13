#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_regional_snowloss_20261013_001
jid=$(cat "$root/job_id.txt")
state=$(squeue -h -j "$jid" -o '%T')
if [ "$state" = PENDING ]; then
  scontrol show partition hcpu48y
  scontrol update JobId="$jid" Partition=hcpu48y
  printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$jid" 'pending job moved hcpu48 to hcpu48y; same four CPUs and six-hour limit' >> "$root/submissions.tsv"
else
  printf 'NO_MOVE_JOB_STATE=%s\n' "$state"
fi
scontrol show job "$jid"
