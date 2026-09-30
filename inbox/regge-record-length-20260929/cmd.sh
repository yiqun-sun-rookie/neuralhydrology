#!/bin/bash
set -eo pipefail

sequence=28
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
OUTPUT=$ROOT/formal_calibration_004
CAPSULE=$ROOT/deploy/formal_calibration_capsule_004
date -Is
squeue -j 232312 -o '%.18i %.24j %.9P %.10T %.30R' || true
sacct -j 232312 --format=JobIDRaw,JobName%24,Partition,State,ExitCode,Elapsed,Start,End,MaxRSS,NCPUS,NodeList -P
for path in "$OUTPUT/batch_started.json" "$OUTPUT/batch_receipt.json" \
    "$OUTPUT/batch_failed.json" \
    "$ROOT/wrapper_receipts/formal_calibration_004-232312.failed.json"; do
  if [ -f "$path" ]; then
    echo "EVIDENCE_FILE=$path"
    cat "$path"
  fi
done
for path in "$ROOT/logs/formal_calibration_004-232312.out" \
    "$ROOT/logs/formal_calibration_004-232312.err" \
    "$OUTPUT/events.jsonl" \
    "$OUTPUT/calibration_process_logs/RL-E1-M06.stdout.log" \
    "$OUTPUT/calibration_process_logs/RL-E1-M06.stderr.log" \
    "$OUTPUT/calibration/RL-E1-M06/events.jsonl"; do
  if [ -f "$path" ]; then
    echo "LOG_FILE=$path"
    tail -n 12 "$path"
  fi
done
sha256sum "$CAPSULE/capsule_manifest.json" "$CAPSULE/calibration_authorization.json"
echo FOURTH_ATTEMPT_STATUS_READ_COMPLETE
