#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/tessera_joint_01073000_20261013_001
JID=$(cat "$ROOT/job_id.txt")
test "$JID" = 241691 || { echo UNEXPECTED_JOB_ID; exit 1; }
STATE=$(squeue -j "$JID" -h -o '%T')
if [ "$STATE" = PENDING ]; then
  scontrol show job "$JID" > "$ROOT/logs/partition_before.txt"
  scontrol update JobId="$JID" Partition=hgpu2p,hgpu4,hgpu8
  printf '%s\n' 'Job 241691 partition eligibility widened to hgpu2p,hgpu4,hgpu8; same single GPU, 4 CPUs, 30 minute budget; no model/data/budget change.' > "$ROOT/logs/partition_override.txt"
  scontrol show job "$JID" > "$ROOT/logs/partition_after.txt"
  echo OWN_PENDING_PARTITION_UPDATED
else
  echo "NO_CHANGE_STATE=$STATE"
fi
date -u
squeue -j "$JID" -h -o '%i %P %j %T %M %R' || true
scontrol show job "$JID" || true
