#!/bin/bash
# Wait for the probe job and report. Login node only sleeps and reads files.
set -o pipefail
RUN=~/kuwei_paired/run_probe
JOB=$(grep -oE '[0-9]+' $RUN/last_jobid.txt 2>/dev/null | tail -1)
echo "=== A. job $JOB ==="
for i in $(seq 1 80); do
  ST=$(squeue -j $JOB -h -o "%T" 2>/dev/null)
  if [ -z "$ST" ]; then echo "job left the queue after ~$((i*15))s"; break; fi
  if [ $((i % 8)) -eq 0 ]; then echo "  t=$((i*15))s state=$ST"; fi
  sleep 15
done

echo "=== B. accounting ==="
sacct -j $JOB --format=JobID,JobName%14,State,ExitCode,Elapsed,NodeList%12,MaxRSS 2>&1 | head -8 || true

echo "=== C. stdout tail ==="
OUT=$(ls -t $RUN/kuwei-probe-*.out 2>/dev/null | head -1)
if [ -n "$OUT" ]; then
  echo "file: $OUT"
  grep -E 'node=|numpy|SPINUP|EXCLUDE_WINDOWS|CALMAP|EvalOpt|FILES|Optimization DONE|NSE|real|Error|Traceback' "$OUT" 2>/dev/null | head -30 || true
  echo "--- last 15 lines ---"
  tail -15 "$OUT" || true
else
  echo "no stdout file"
fi

echo "=== D. stderr tail (first errors only) ==="
ERR=$(ls -t $RUN/kuwei-probe-*.err 2>/dev/null | head -1)
if [ -n "$ERR" ] && [ -s "$ERR" ]; then
  echo "file: $ERR"; head -30 "$ERR" || true
else
  echo "(stderr empty or absent)"
fi

echo "=== E. did it produce parameters? ==="
ls -la $RUN/out/*.yml 2>/dev/null | head -5 || echo "(no yml produced)"
echo "=== DONE ==="
