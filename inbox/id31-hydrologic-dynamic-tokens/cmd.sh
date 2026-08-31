#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
JOB_ID=216541

test -d "$ROOT/.git"
cd "$ROOT"

echo "=== CURRENT PROBE ==="
squeue -j "$JOB_ID" -o '%.18i %.24j %.12P %.2t %.10l %.19S %.30R' || true
scontrol show job "$JOB_ID" -o || true

echo "=== RTX-3090 PARTITION LIVE INVENTORY ==="
for PARTITION in hgpu2p hgpu2; do
  echo "--- PARTITION $PARTITION ---"
  sinfo -p "$PARTITION" -N -o '%12P|%16N|%8t|%24G|%20C' || true
  scontrol show partition "$PARTITION" -o || true
done

echo "=== USER GPU JOBS ==="
squeue -u sunyiq -o '%.18i %.24j %.12P %.2t %.10M %.10l %.30R' || true

echo "=== PARTITION QUEUE SUMMARY ==="
squeue -p hgpu2p,hgpu2 -o '%.18i %.24j %.12P %.2t %.10M %.10l %.30R' || true

echo "ID31_GPU_PARTITION_SURVEY_COMPLETE"
