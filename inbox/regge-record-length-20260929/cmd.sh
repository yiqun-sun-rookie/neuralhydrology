#!/bin/bash
set -eo pipefail

sequence=22
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
WORK=$ROOT/formal_calibration_003
EXP=RL-E1-M06
CAL=$WORK/calibration/$EXP
LOGS=$WORK/calibration_process_logs

echo "=== FILE INVENTORY ==="
find "$CAL" "$LOGS" -maxdepth 2 -type f -printf '%p|%s bytes\n' | sort
echo "=== EXPERIMENT FILES ==="
for path in "$CAL/process.json" "$CAL/receipt.json" "$CAL/result.json" \
    "$CAL/events.jsonl" "$LOGS/$EXP.stdout.log" "$LOGS/$EXP.stderr.log"; do
  echo "--- $path"
  if [ -f "$path" ]; then
    cat "$path"
  else
    echo "MISSING"
  fi
done
echo "=== CHECKSUMS ==="
find "$CAL" "$LOGS" -maxdepth 2 -type f -print0 \
  | sort -z | xargs -0 sha256sum
