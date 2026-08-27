#!/bin/bash
set -eo pipefail

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
JOB_ID=$(tr -d '[:space:]' < "$TARGET/deployment/preselection_gates_job_id_v01.txt")
JOB_NUM=$(printf '%s' "$JOB_ID" | cut -d';' -f1)

echo "=== LIVE GPU PARTITION INVENTORY ==="
date -Is
hostname
sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -o '%.10P %.6a %.6D %.6t %.30N %.12G' || true
echo "=== NODE DETAIL ==="
sinfo -N -p hgpu2p,hgpu2,hgpu4,hgpu8 -o '%.12N %.10P %.10T %.8c %.12G %.30E' || true
echo "=== QUEUED GPU JOBS ==="
squeue -p hgpu2p,hgpu2,hgpu4,hgpu8 -o '%.18i %.10P %.24j %.10u %.8T %.10M %.20l %.30R' || true
echo "=== CURRENT JOB ESTIMATE ==="
squeue -j "$JOB_NUM" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
squeue --start -j "$JOB_NUM" -o '%.18i %.12P %.28j %.19S %.30R' || true
sacct -j "$JOB_NUM" --format=JobID,JobName,Partition,State,ExitCode,Elapsed,NodeList -n -P || true
