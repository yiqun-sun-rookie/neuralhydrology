#!/bin/bash
# precip-selfrule-v05 seq=18: read-only status of batch-384 resource/equivalence probe.
set -o pipefail

ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_batch384_probe_20260929
OUT="$ROOT/candidate_batch384/run01"
JOB=231323

date "+wallclock %F %T %z"
squeue -j "$JOB" -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true
sacct -j "$JOB" --format=JobID,JobName%24,State,ExitCode,Elapsed,AllocTRES%40,MaxRSS,NodeList%14 -P || true
if test -f "$OUT/batch_probe_comparison.json"; then
  echo "=== BATCH PROBE COMPARISON ==="
  cat "$OUT/batch_probe_comparison.json"
else
  echo "BATCH_PROBE_COMPARISON_PENDING"
fi
if test -f "$ROOT/logs/probe-$JOB.out"; then
  echo "=== STDOUT TAIL ==="
  tail -80 "$ROOT/logs/probe-$JOB.out"
fi
if test -s "$ROOT/logs/probe-$JOB.err"; then
  echo "=== STDERR TAIL ==="
  tail -80 "$ROOT/logs/probe-$JOB.err"
fi
