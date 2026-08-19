#!/bin/bash
# ID29 seq=286: post-runner-restart probe + progress on the two repair reruns.
set -o pipefail
echo "=== RUNNER + TIME ==="
date --iso-8601=seconds
pgrep -af hpc_runner_active | head -3 || echo 'runner process not matched'
echo "=== REPAIR RERUNS ==="
sacct -X -n -P -j 204860,204861 --format=JobID,State,Elapsed,Timelimit,NodeList 2>/dev/null || true
for J in 204860_6 204861_7; do
  SO=$(scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^StdOut=//p' | head -1)
  [ -n "$SO" ] && [ -f "$SO" ] && { printf -- '--- %s ---\n' "$J"; tail -c 120000 "$SO" 2>/dev/null | tr '\r' '\n' | grep -iE '^# Epoch' | tail -1 || true; }
done
echo "=== MY OTHER JOBS ==="
squeue -u sunyiq -h -o '%.12i %.14j %.9T %.11M %.11L' 2>/dev/null | head -12 || true
echo "=== END seq=286 ==="; date --iso-8601=seconds
exit 0
