#!/usr/bin/env bash
set -eo pipefail
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_state_update_control_20260921_v1"
readonly EXPECTED_AGGREGATE_SHA="9e801d2e858fcae945ba783a123f1fd22f3fbc64911d341a86ca0b05292016e4"
echo "FIXED_CONTROL_REMAINING_PAIR_READ_ONLY_TRANSFER_V1"
echo "sequence=193"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s  %s\n' "$EXPECTED_AGGREGATE_SHA" "$OUTPUT_ROOT/aggregate.json" | sha256sum --check --strict
primary_ids=(
  CTRL-02092500-NETWORK-20260824-FULL3288
  CTRL-02092500-NETWORK-20260901-FULL3288
  CTRL-02092500-NETWORK-20260908-FULL3288
  CTRL-02092500-NETWORK-20260915-FULL3288
  CTRL-02092500-NETWORK-20260922-FULL3288
  CTRL-02092500-NOUPDATE-NONE-FULL3288
)
echo "PRIMARY_PAIR_HASHES_BEGIN"
for id in "${primary_ids[@]}"; do
  file="$OUTPUT_ROOT/runs/$id/forecast_pairs.npz"
  if [[ ! -f "$file" || -L "$file" ]]; then echo "REFUSING: primary pair file absent or symlink" >&2; exit 20; fi
  stat -c "$id bytes=%s" "$file"
  sha256sum "$file"
done
echo "PRIMARY_PAIR_HASHES_END"
ids=(
  CTRL-02092500-NETWORK-20260824-RESTART731
  CTRL-02092500-NETWORK-20260901-RESTART731
  CTRL-02092500-NETWORK-20260908-RESTART731
  CTRL-02092500-NETWORK-20260915-RESTART731
  CTRL-02092500-NETWORK-20260922-RESTART731
  CTRL-02092500-UNSCENTED-20260824-FULL3288
  CTRL-02092500-UNSCENTED-20260824-RESTART731
  CTRL-02092500-UNSCENTED-20260901-FULL3288
  CTRL-02092500-UNSCENTED-20260901-RESTART731
  CTRL-02092500-UNSCENTED-20260908-FULL3288
  CTRL-02092500-UNSCENTED-20260908-RESTART731
  CTRL-02092500-UNSCENTED-20260915-FULL3288
  CTRL-02092500-UNSCENTED-20260915-RESTART731
  CTRL-02092500-UNSCENTED-20260922-FULL3288
  CTRL-02092500-UNSCENTED-20260922-RESTART731
  CTRL-02092500-NOUPDATE-NONE-RESTART731
)
total=0
for id in "${ids[@]}"; do
  file="$OUTPUT_ROOT/runs/$id/forecast_pairs.npz"
  if [[ ! -f "$file" || -L "$file" ]]; then echo "REFUSING: expected pair file absent or symlink" >&2; exit 21; fi
  size=$(stat -c '%s' "$file")
  if [[ "$size" -gt 200000 ]]; then echo "REFUSING: individual pair file too large" >&2; exit 22; fi
  total=$((total + size))
done
if [[ "$total" -gt 700000 ]]; then echo "REFUSING: total pair transfer too large" >&2; exit 23; fi
echo "total_pair_bytes=$total"
for id in "${ids[@]}"; do
  file="$OUTPUT_ROOT/runs/$id/forecast_pairs.npz"
  echo "PAIR_BEGIN $id"
  stat -c 'bytes=%s' "$file"
  sha256sum "$file"
  base64 --wrap=0 "$file"
  echo
  echo "PAIR_END $id"
done
echo "OWN_QUEUE_BEGIN"
squeue -u "$USER" -h -o '%i|%j|%T|%P|%R' || echo "OWN_QUEUE_READ_FAILED"
echo "OWN_QUEUE_END"
