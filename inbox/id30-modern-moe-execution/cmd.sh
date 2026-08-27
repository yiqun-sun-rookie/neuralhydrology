#!/bin/bash
set -euo pipefail

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
ROOT="$TARGET/repo"
JOB_ID=$(tr -d '[:space:]' < "$TARGET/deployment/safe_data_job_id_v03.txt")
JOB_NUM=$(printf '%s' "$JOB_ID" | cut -d';' -f1)

echo "=== SAFE DATA V03 STATUS ==="
date -Is
hostname
echo "job_id=$JOB_NUM"
squeue -j "$JOB_NUM" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
sacct -j "$JOB_NUM" --format=JobID,JobName,Partition,State,ExitCode,Elapsed,NodeList -n -P || true

echo "=== LOG TAILS ==="
for log in "$ROOT"/logs/30_modern_transformer_moe/prepare-track0-"$JOB_NUM".out \
           "$ROOT"/logs/30_modern_transformer_moe/prepare-track0-"$JOB_NUM".err; do
  echo "--- $log"
  if [ -f "$log" ]; then
    tail -160 "$log"
  else
    echo "NOT_CREATED"
  fi
done

echo "=== PRODUCT INVENTORY ==="
for path in \
  "$ROOT/data/camels_us_track0_development_forcing_v01" \
  "$ROOT/data/camels_us_track0_supervision_v01" \
  "$ROOT/src/modern_transformer_moe/registry/track0_development_forcing_manifest_v01.json" \
  "$ROOT/src/modern_transformer_moe/registry/track0_supervision_manifest_v01.json" \
  "$ROOT/results/30_modern_transformer_moe/_reports/track0_bundle_audit.json"; do
  if [ -d "$path" ]; then
    echo "DIRECTORY $(find "$path" -type f | wc -l) $path"
  elif [ -f "$path" ]; then
    echo "FILE $(stat -c '%s' "$path") $(sha256sum "$path" | awk '{print $1}') $path"
  else
    echo "ABSENT $path"
  fi
done

AUDIT="$ROOT/results/30_modern_transformer_moe/_reports/track0_bundle_audit.json"
if [ -f "$AUDIT" ]; then
  echo "=== BOUNDARY AUDIT REPORT ==="
  cat "$AUDIT"
fi
