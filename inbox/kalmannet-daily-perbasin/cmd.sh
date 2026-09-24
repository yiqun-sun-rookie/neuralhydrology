#!/usr/bin/env bash
set -eo pipefail
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_coldstart_stress_development_20260924_v1"
readonly EXPECTED_AGGREGATE_SHA="31cf39ce1ac7875ee003d4a5a6fc77229f386b9bc5bebc0ff1db686b691170af"
echo "COLDSTART_STRESS_ARRAY_READ_ONLY_TRANSFER_V1"
echo "sequence=198"
echo "batch=2"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s  %s\n' "$EXPECTED_AGGREGATE_SHA" "$OUTPUT_ROOT/aggregate.json" | sha256sum --check --strict
files=(
  runs/STRESS-02092500-NETWORK-20260824-COLD20001001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260824-COLD20011001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260824-COLD20021001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260824-COLD20031001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260824-COLD20041001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260824-COLD20051001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260824-COLD20061001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260901-COLD20001001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260901-COLD20011001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260901-COLD20021001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260901-COLD20031001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260901-COLD20041001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260901-COLD20051001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260901-COLD20061001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260908-COLD20001001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260908-COLD20011001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260908-COLD20021001/arrays.npz
  runs/STRESS-02092500-NETWORK-20260908-COLD20031001/arrays.npz
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
