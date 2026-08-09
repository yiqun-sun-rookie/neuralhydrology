#!/bin/bash
# id26-v09-strict seq=22 : lightweight per-arm timing query, no waiting loop.
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
CODE=$ROOT/codetest/neuralhydrology
JID=$(cat "$ROOT/suite_jobid.txt" 2>/dev/null || echo 201861)
echo "=== JOB ==="
sacct -j "$JID" -X --format=JobID%10,State%12,ExitCode%8,Start%20,End%20,Elapsed%12 2>&1 | head -4
echo "=== LOG MARKERS ==="
grep -nE '^(node=|start=|end=)|"run_id"' "$ROOT/logs/suite_${JID}.out" 2>&1
echo "=== RUN FILE TIMES ==="
BASE=$CODE/results/26_historical_band_experts/formal_v09
for family in classic capacity continuous; do
  d="$BASE/$family/seed_100"
  echo "--- $family ---"
  stat -c 'dir|birth=%w|mtime=%y|change=%z' "$d" 2>&1
  stat -c '%n|birth=%w|mtime=%y|change=%z|bytes=%s' "$d/manifest.json" "$d/seal.json" 2>&1
done
echo "=== JOB FILES ==="
ls -lt --full-time "$ROOT/jobs" 2>&1 | head -12
echo "=== END ==="
