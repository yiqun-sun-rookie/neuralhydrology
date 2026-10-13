#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/tessera_joint_01073000_20261013_001
JID=$(cat "$ROOT/job_id.txt")
test "$JID" = 241691 || { echo UNEXPECTED_JOB_ID; exit 1; }
STATE=$(squeue -j "$JID" -h -o '%T')
if [ "$STATE" = PENDING ]; then
  INFO=$(scontrol show job "$JID" -o)
  case "$INFO" in
    *"WorkDir=$ROOT"*) scontrol hold "$JID" ;;
    *) echo WRONG_WORK_DIRECTORY_NO_ACTION; exit 1 ;;
  esac
  echo HELD_OWN_JOB_FOR_CONFIRMED_STATIC_FEATURE_ORDER_BUG
else
  echo "NO_HOLD_STATE=$STATE"
fi
squeue -j "$JID" -h -o '%i %P %j %T %M %R' || true
