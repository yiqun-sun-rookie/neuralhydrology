#!/bin/bash
set -eo pipefail

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
ROOT="$TARGET/repo"
JOB_ID=$(tr -d '[:space:]' < "$TARGET/deployment/safe_data_job_id.txt")
JOB_ID=${JOB_ID%%;*}

echo "=== SAFE DATA JOB STATUS ==="
date -Is
hostname
echo "job_id=$JOB_ID"
squeue -j "$JOB_ID" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
sacct -j "$JOB_ID" --format=JobID,JobName,Partition,State,ExitCode,Elapsed,NodeList -n -P || true

echo "=== LOG TAILS ==="
for log in "$ROOT"/logs/30_modern_transformer_moe/prepare-track0-"$JOB_ID".out \
           "$ROOT"/logs/30_modern_transformer_moe/prepare-track0-"$JOB_ID".err; do
  echo "--- $log"
  if [ -f "$log" ]; then
    tail -80 "$log"
  else
    echo "NOT_CREATED"
  fi
done

echo "=== PUBLISHED PRODUCTS ==="
for path in \
  "$ROOT/data/camels_us_track0_development_forcing_v01" \
  "$ROOT/data/camels_us_track0_supervision_v01" \
  "$ROOT/src/modern_transformer_moe/registry/track0_development_forcing_manifest_v01.json" \
  "$ROOT/src/modern_transformer_moe/registry/track0_supervision_manifest_v01.json" \
  "$ROOT/results/30_modern_transformer_moe/_reports/track0_bundle_audit.json"; do
  if [ -d "$path" ]; then
    echo "DIRECTORY $(find "$path" -type f | wc -l) $path"
  elif [ -f "$path" ]; then
    echo "FILE $(stat -c '%s' "$path") $path"
  else
    echo "ABSENT $path"
  fi
done
