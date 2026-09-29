#!/usr/bin/env bash
set -eo pipefail
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_slz_survey_development_20260928_v1"
readonly EXPECTED_AGGREGATE_SHA="ffc8c51ed3c5fd5defeae4b7dcf9b36e06c4f04bbce6898d2483be0d76b09c92"
echo "SLZ_SURVEY_READ_ONLY_TRANSFER_V1"
echo "sequence=240"
echo "batch=12"
echo "kind=necessary"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s  %s\n' "$EXPECTED_AGGREGATE_SHA" "$OUTPUT_ROOT/aggregate.json" | sha256sum --check --strict
files=(
  part_a/seed_20260922/epoch_045_all.npz
  part_a/seed_20260922/epoch_046_all.npz
  part_a/seed_20260922/epoch_047_all.npz
  part_a/seed_20260922/epoch_048_all.npz
  part_a/seed_20260922/epoch_049_all.npz
)
total=0
for rel in "${files[@]}"; do
  file="$OUTPUT_ROOT/$rel"
  if [[ ! -f "$file" || -L "$file" ]]; then echo "REFUSING: expected file absent or symlink: $rel" >&2; exit 21; fi
  total=$((total + $(stat -c '%s' "$file")))
done
if [[ "$total" -gt 520000 ]]; then echo "REFUSING: batch too large total=$total" >&2; exit 22; fi
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
