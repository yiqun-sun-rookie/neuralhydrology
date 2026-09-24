#!/usr/bin/env bash
set -eo pipefail
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_coldstart_stress_development_20260924_v1"
readonly EXPECTED_AGGREGATE_SHA="31cf39ce1ac7875ee003d4a5a6fc77229f386b9bc5bebc0ff1db686b691170af"
echo "COLDSTART_STRESS_ARRAY_READ_ONLY_TRANSFER_V1"
echo "sequence=197"
echo "batch=1"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s  %s\n' "$EXPECTED_AGGREGATE_SHA" "$OUTPUT_ROOT/aggregate.json" | sha256sum --check --strict
files=(
  starts/2000-10-01/targets.npz
  starts/2001-10-01/targets.npz
  starts/2002-10-01/targets.npz
  starts/2003-10-01/targets.npz
  starts/2004-10-01/targets.npz
  starts/2005-10-01/targets.npz
  starts/2006-10-01/targets.npz
)
total=0
for rel in "${files[@]}"; do
  file="$OUTPUT_ROOT/$rel"
  if [[ ! -f "$file" || -L "$file" ]]; then echo "REFUSING: expected array file absent or symlink: $rel" >&2; exit 21; fi
  total=$((total + $(stat -c '%s' "$file")))
done
if [[ "$total" -gt 690000 ]]; then echo "REFUSING: batch too large total=$total" >&2; exit 22; fi
echo "total_bytes=$total"
for rel in "${files[@]}"; do
  file="$OUTPUT_ROOT/$rel"
  echo "FILE_BEGIN $rel"
  stat -c 'bytes=%s' "$file"
  sha256sum "$file" | awk '{print $1}'
  base64 --wrap=0 "$file"
  echo
  echo "FILE_END $rel"
done
