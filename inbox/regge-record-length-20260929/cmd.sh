#!/bin/bash
set -eo pipefail
sequence=4

JOB_ID=231216
PROBE=/data1/home/sunyiq/regge_record_length_20260929_001/runtime_probe_001

echo "=== queue ==="
squeue -j "$JOB_ID" -o '%.18i %.12P %.28j %.2t %.10M %.10l %.24R' || true
echo "=== accounting ==="
sacct -j "$JOB_ID" --format=JobID,JobName%28,Partition,State,ExitCode,Elapsed,AllocCPUS,NodeList -P || true
echo "=== receipts ==="
for path in "$PROBE/submission_receipt.txt" "$PROBE/runtime_success.txt" "$PROBE/runtime_failed.txt" "$PROBE/conda-explicit.sha256"; do
  if test -f "$path"; then
    echo "--- $path"
    cat "$path"
  else
    echo "ABSENT $path"
  fi
done
echo "=== logs ==="
for path in "$PROBE"/logs/runtime-"$JOB_ID".out "$PROBE"/logs/runtime-"$JOB_ID".err; do
  if test -f "$path"; then
    echo "--- $path"
    tail -n 60 "$path"
  else
    echo "ABSENT $path"
  fi
done
