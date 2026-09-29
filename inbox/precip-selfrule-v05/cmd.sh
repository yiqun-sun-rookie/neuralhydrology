#!/bin/bash
# precip-selfrule-v05 seq=31: bounded read-only terminal check for concurrency probe 231412.
set -o pipefail

ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_concurrency4_probe_20260929
OUT="$ROOT/candidate_concurrency4/run01"
JOB=231412

date "+wallclock %F %T %z"
squeue -j "$JOB" -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true
sacct -j "$JOB" --format=JobIDRaw,JobName%24,State,ExitCode,Elapsed,ElapsedRaw,AllocTRES%40,MaxRSS,NodeList%14 -P || true
for log in "$ROOT"/logs/probe-"$JOB".out "$ROOT"/logs/probe-"$JOB".err; do
  if [ -f "$log" ]; then
    echo "=== $log ==="
    tail -80 "$log"
  fi
done
for artifact in "$OUT/concurrency_timing.json" "$OUT/concurrency_probe_comparison.json"; do
  if [ -f "$artifact" ]; then
    echo "=== $artifact ==="
    cat "$artifact"
    sha256sum "$artifact"
  fi
done
