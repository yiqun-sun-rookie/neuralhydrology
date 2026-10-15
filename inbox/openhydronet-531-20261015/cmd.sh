#!/bin/bash
set -o pipefail
# read-only: state and log tails of this channel's jobs (job ids passed through the file next to it)
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
date --iso-8601=seconds
echo "=== queue (ohn_*) ==="
squeue -u sunyiq -h -o '%.10i %.14j %.9T %.10M %R' | grep -E ' ohn_' || echo "none queued/running"
echo "=== sacct today (ohn_*) ==="
sacct -X -n -P -S 2026-10-15 --format=JobID,JobName,State,ExitCode,Elapsed,NodeList 2>/dev/null | grep -E '\|ohn_' || echo none
for J in $(sacct -X -n -P -S 2026-10-15 --format=JobID,JobName 2>/dev/null | grep -E '\|ohn_' | cut -d'|' -f1 | tail -2); do
  N=$(sacct -X -n -P -j $J --format=JobName | head -1)
  for E in out err; do
    F="$ROOT/logs/$N-$J.$E"
    if [ -f "$F" ]; then echo "--- $F ($(stat -c %s "$F") bytes)"; tail -n 14 "$F" | tr '\r' '\n' | tail -n 14 | cut -c1-230; fi
  done
done
exit 0
