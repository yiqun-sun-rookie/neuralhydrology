#!/usr/bin/env bash
set -eo pipefail
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_coldstart_intervention_development_20260927_v1"
readonly EXPECTED_AGGREGATE_SHA="6a4928d7fa88ea68d2723505abd6af173dd777cf1ed3427e7e90057a4f086f0a"
echo "COLDSTART_INTERVENTION_ARRAY_READ_ONLY_TRANSFER_V1"
echo "sequence=209"
echo "batch=5"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s  %s\n' "$EXPECTED_AGGREGATE_SHA" "$OUTPUT_ROOT/aggregate.json" | sha256sum --check --strict
files=(
  runs/INTV-02092500-NETWORK-20260908-COLD20031001-R3_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260908-COLD20041001-R1_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260908-COLD20041001-R2_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260908-COLD20041001-R2_800/arrays.npz
  runs/INTV-02092500-NETWORK-20260908-COLD20041001-R3_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260908-COLD20051001-R1_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260908-COLD20051001-R2_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260908-COLD20051001-R2_800/arrays.npz
  runs/INTV-02092500-NETWORK-20260908-COLD20051001-R3_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260908-COLD20061001-R1_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260908-COLD20061001-R2_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260908-COLD20061001-R3_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260915-COLD20001001-R1_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260915-COLD20001001-R2_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260915-COLD20001001-R2_800/arrays.npz
  runs/INTV-02092500-NETWORK-20260915-COLD20001001-R3_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260915-COLD20011001-R1_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260915-COLD20011001-R2_150/arrays.npz
  runs/INTV-02092500-NETWORK-20260915-COLD20011001-R2_800/arrays.npz
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
