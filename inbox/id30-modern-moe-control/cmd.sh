#!/bin/bash
set -eo pipefail

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
STAGING="$HOME/.hpc_mailbox_staging/id30-modern-moe-execution/result_5.txt"

echo "=== CONTROL CHANNEL HEALTH ==="
date -Is
hostname
pgrep -af hpc_runner_active || true
echo "=== MAIN CHANNEL STAGING ==="
if [ -f "$STAGING" ]; then
  stat -c '%n %s bytes %y' "$STAGING"
  tail -100 "$STAGING"
else
  echo "RESULT_5_STAGING_ABSENT"
fi
echo "=== TARGET STATE ==="
if [ -d "$TARGET/repo/.git" ]; then
  git -C "$TARGET/repo" rev-parse HEAD
  git -C "$TARGET/repo" status --short | head -80 || true
fi
if [ -f "$TARGET/deployment/safe_data_job_id_v02.txt" ]; then
  JOB_ID=$(tr -d '[:space:]' < "$TARGET/deployment/safe_data_job_id_v02.txt")
  JOB_ID=${JOB_ID%%;*}
  echo "safe_data_job_id_v02=$JOB_ID"
  squeue -j "$JOB_ID" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
  sacct -j "$JOB_ID" --format=JobID,JobName,Partition,State,ExitCode,Elapsed,NodeList -n -P || true
else
  echo "SAFE_DATA_JOB_ID_V02_ABSENT"
fi
