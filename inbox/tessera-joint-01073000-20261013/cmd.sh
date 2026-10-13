#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/tessera_joint_01073000_20261013_001
JID=$(cat "$ROOT/job_id.txt")
test "$JID" = 241691 || { echo UNEXPECTED_JOB_ID; exit 1; }
STATE=$(squeue -j "$JID" -h -o '%T')
if [ "$STATE" = PENDING ]; then
  /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python "$HOME/hpc_mailbox/inbox/tessera-joint-01073000-20261013/payload/patch_absolute_config.py"
  cd "$ROOT"
  sha256sum -c MANIFEST.sha256 > logs/input_verification_after_path_fix.txt
  echo QUEUED_LAUNCH_FIX_CONFIRMED
else
  echo "NO_PATCH_STATE=$STATE"
fi
squeue -j "$JID" -h -o '%i %P %j %T %M %R' || true
