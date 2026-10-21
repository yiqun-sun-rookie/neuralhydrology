#!/bin/bash
# seq5: read-only status of array 244280; if every task finished, emit all records as base64 tar.gz.
set -o pipefail
ROOT=/data1/home/sunyiq/hydrol85935_prepeak_small_bounds_20261017_001
AJ=$(cat "$ROOT/control/array_jobid.txt")
echo "=== ARRAY $AJ ==="
sacct -j "$AJ" -X --format=JobID%-14,State%-12,ExitCode,NodeList,Elapsed -n 2>&1
squeue -j "$AJ" -h -o '%i %T %R' 2>&1
echo "=== RECORDS ==="
N=$(ls "$ROOT/out/records" 2>/dev/null | grep -c '\.json$')
echo "n_records=$N"
echo "n_error=$(grep -l '"status": "error"' "$ROOT"/out/records/*.json 2>/dev/null | wc -l)"
echo "=== LOG TAILS ==="
for f in "$ROOT"/logs/prepeak-${AJ}_*.out; do [ -f "$f" ] && { echo "--- $(basename $f)"; tail -3 "$f"; }; done
for f in "$ROOT"/logs/prepeak-${AJ}_*.err; do [ -s "$f" ] && { echo "--- $(basename $f) (non-empty)"; tail -5 "$f"; }; done
NOT_DONE=$(sacct -j "$AJ" -X --format=State -n -P 2>/dev/null | grep -vc '^COMPLETED$')
if [ "$NOT_DONE" = "0" ]; then
  echo "=== RECORDS_TGZ_BASE64_BEGIN ==="
  tar -C "$ROOT/out" -czf - records | base64 -w 0
  echo
  echo "=== RECORDS_TGZ_BASE64_END ==="
else
  echo "NOT_ALL_COMPLETED ($NOT_DONE tasks not COMPLETED)"
fi
