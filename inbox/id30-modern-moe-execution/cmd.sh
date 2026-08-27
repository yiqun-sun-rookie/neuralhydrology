#!/bin/bash
set -eo pipefail

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
JOB_ID=$(tr -d '[:space:]' < "$TARGET/deployment/preselection_gates_job_id_v01.txt")
JOB_NUM=$(printf '%s' "$JOB_ID" | cut -d';' -f1)

echo "=== VERIFY PENDING JOB ==="
date -Is
hostname
CURRENT_STATE=$(squeue -h -j "$JOB_NUM" -o '%T')
CURRENT_PARTITION=$(squeue -h -j "$JOB_NUM" -o '%P')
echo "job_id=$JOB_NUM state=$CURRENT_STATE partition=$CURRENT_PARTITION"
test "$CURRENT_STATE" = "PENDING"
test "$CURRENT_PARTITION" = "hgpu2p"

echo "=== MOVE TO RTX 3090 EQUIVALENT PARTITION ==="
scontrol update jobid="$JOB_NUM" partition=hgpu2
sleep 2
squeue -j "$JOB_NUM" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
squeue --start -j "$JOB_NUM" -o '%.18i %.12P %.28j %.19S %.30R' || true
scontrol show job "$JOB_NUM" | tr ' ' '\n' | grep -E '^(JobId|JobState|Partition|NodeList|ExcNodeList|ReqTRES)=' || true
echo "=== COMPLETE ==="
date -Is
