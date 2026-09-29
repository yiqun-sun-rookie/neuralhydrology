#!/bin/bash
# precip-selfrule-v05 seq=4: read-only status after gated technical submission.
set -o pipefail
ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_20260929

date "+wallclock %F %T %z"
hostname

echo "=== A. QUEUE ==="
squeue -j 231221,231222 -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true

echo "=== B. ACCOUNTING ==="
sacct -j 231221,231222 --format=JobID,JobName%24,State,ExitCode,Elapsed,NodeList%14 -P || true

echo "=== C. RUNTIME GATE ==="
if [ -f "$ROOT/technical_8/run01/runtime_validation.json" ]; then
  cat "$ROOT/technical_8/run01/runtime_validation.json"
else
  echo "RUNTIME_VALIDATION_PENDING"
fi

echo "=== D. COMPLETED BASIN RECORDS ==="
find "$ROOT/technical_8/run01/fit" -maxdepth 1 -type f -name '*.json' -printf '%f %s bytes
' 2>/dev/null | sort || true
find "$ROOT/technical_8/run01/fit_summaries" -maxdepth 1 -type f -name '*.json' -printf '%f %s bytes
' 2>/dev/null | sort || true

echo "=== E. LOG TAILS ==="
for f in "$ROOT"/logs/runtime-231221.out "$ROOT"/logs/runtime-231221.err "$ROOT"/logs/technical-231222_*.out "$ROOT"/logs/technical-231222_*.err; do
  if [ -f "$f" ]; then
    echo "--- $f"
    tail -n 25 "$f"
  fi
done
echo "=== STATUS CHECK COMPLETE ==="