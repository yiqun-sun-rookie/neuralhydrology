#!/bin/bash
set -eo pipefail

sequence=21
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
JOB_ID=231464
OUTPUT=$ROOT/formal_calibration_003
STDOUT=$ROOT/logs/formal_calibration_003-$JOB_ID.out
STDERR=$ROOT/logs/formal_calibration_003-$JOB_ID.err
SUBMISSION=$ROOT/submission_receipts/formal_calibration_003-$JOB_ID.json
WRAPPER_FAILURE=$ROOT/wrapper_receipts/formal_calibration_003-$JOB_ID.failed.json

echo "=== SQUEUE ==="
squeue -j "$JOB_ID" -o '%.18i %.24j %.9P %.10T %.12M %.30R' || true
echo "=== SACCT ==="
sacct -j "$JOB_ID" --format=JobID,JobName%24,Partition,State,ExitCode,Elapsed,Start,End -P || true
echo "=== RECEIPTS ==="
for path in "$SUBMISSION" "$OUTPUT/batch_started.json" \
    "$OUTPUT/batch_receipt.json" "$OUTPUT/batch_failed.json" \
    "$WRAPPER_FAILURE"; do
  if [ -f "$path" ]; then
    echo "--- $path"
    cat "$path"
  else
    echo "MISSING $path"
  fi
done
echo "=== STDOUT TAIL ==="
if [ -f "$STDOUT" ]; then tail -n 40 "$STDOUT"; else echo "MISSING $STDOUT"; fi
echo "=== STDERR TAIL ==="
if [ -f "$STDERR" ]; then tail -n 40 "$STDERR"; else echo "MISSING $STDERR"; fi
