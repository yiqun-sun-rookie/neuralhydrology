#!/usr/bin/env bash
set -eo pipefail
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_training_mode_replay_development_20260927_v1"
readonly EXPECTED_AGGREGATE_SHA="c83bac15b1ebcd4501bf70a91d7a56849c5c382dc2256442534c57da24fcb796"
echo "TRAINING_MODE_REPLAY_ARRAY_READ_ONLY_TRANSFER_V1"
echo "sequence=222"
echo "batch=3"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s  %s\n' "$EXPECTED_AGGREGATE_SHA" "$OUTPUT_ROOT/aggregate.json" | sha256sum --check --strict
files=(
  runs/REPLAY-02092500-NETWORK-20260922-SEG2006-T/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2061-PC1461/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2061-PT/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2081-PC0731/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2081-PT/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2106-C0366/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2106-C0731/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2106-C1096/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2106-C1461/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2106-C1827/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2106-CS0366/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2106-CS0731/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2106-CS1096/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2106-CS1461/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2106-CS1827/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2106-G/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2106-T/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2127-PC1827/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2127-PT/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2146-PC1096/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2146-PT/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2207-T/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2307-T/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2407-C0366/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2407-C0731/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2407-C1096/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2407-C1461/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2407-C1827/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2407-C2192/arrays.npz
  runs/REPLAY-02092500-NETWORK-20260922-SEG2407-T/arrays.npz
)
total=0
for rel in "${files[@]}"; do
  file="$OUTPUT_ROOT/$rel"
  if [[ ! -f "$file" || -L "$file" ]]; then echo "REFUSING: expected array file absent or symlink: $rel" >&2; exit 21; fi
  total=$((total + $(stat -c '%s' "$file")))
done
if [[ "$total" -gt 600000 ]]; then echo "REFUSING: batch too large total=$total" >&2; exit 22; fi
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
