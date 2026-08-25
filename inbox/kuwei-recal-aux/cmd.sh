#!/bin/bash
# Auxiliary channel: the main kuwei channel is stuck. Read state WITHOUT touching it.
set -o pipefail
RUN=~/kuwei_paired/run_probe
echo "=== A. job state ==="
JOB=$(grep -oE '[0-9]+' $RUN/last_jobid.txt 2>/dev/null | tail -1); echo "jobid=$JOB"
squeue -j $JOB -o "%.10i %.12j %.10P %.8T %.10M %R" 2>&1 | head -4 || true
sacct -j $JOB --format=JobID,State,ExitCode,Elapsed,NodeList%12 2>&1 | head -6 || true

echo "=== B. probe stdout ==="
OUT=$(ls -t $RUN/kuwei-probe-*.out 2>/dev/null | head -1)
if [ -n "$OUT" ]; then
  echo "file=$OUT size=$(stat -c%s "$OUT")"
  grep -E 'node=|numpy |SPINUP|EXCLUDE_WINDOWS|CALMAP|EvalOpt|Optimization DONE|NSE|^real' "$OUT" 2>/dev/null | head -25 || true
  echo "--- tail 12 ---"; tail -12 "$OUT" || true
else echo "(no .out yet)"; fi

echo "=== C. probe stderr ==="
ERR=$(ls -t $RUN/kuwei-probe-*.err 2>/dev/null | head -1)
if [ -n "$ERR" ] && [ -s "$ERR" ]; then echo "file=$ERR"; head -25 "$ERR" || true; else echo "(empty)"; fi

echo "=== D. produced parameter files ==="
ls -la $RUN/out/*.yml 2>/dev/null | head -4 || echo "(none)"

echo "=== E. is the main channel's seq=5 result sitting in staging? ==="
ls -la ~/.hpc_mailbox_staging/kuwei-paired-recal/result_5.txt 2>/dev/null || echo "(no staged result_5)"
echo "=== DONE ==="
