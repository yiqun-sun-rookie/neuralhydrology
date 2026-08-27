#!/bin/bash
set -eo pipefail

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
ROOT="$TARGET/repo"
JOB_ID=$(tr -d '[:space:]' < "$TARGET/deployment/safe_data_job_id_v02.txt")
JOB_ID=${JOB_ID%%;*}

echo "=== SAFE DATA FAST STATUS ==="
date -Is
hostname
echo "job_id=$JOB_ID"
squeue -j "$JOB_ID" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
sacct -j "$JOB_ID" --format=JobID,JobName,Partition,State,ExitCode,Elapsed,NodeList -n -P || true
echo "=== LOG TAIL ==="
tail -80 "$ROOT/logs/30_modern_transformer_moe/prepare-track0-${JOB_ID}.out" 2>/dev/null || true
tail -80 "$ROOT/logs/30_modern_transformer_moe/prepare-track0-${JOB_ID}.err" 2>/dev/null || true
