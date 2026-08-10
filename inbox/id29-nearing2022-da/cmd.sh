#!/bin/bash
# ID29 seq=95: inspect preclosure validation job 202365 and its immutable logs; keep candidate manifest 202293 held.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOB=202365
OUT="$ROOT/closure_20260810/logs/N22-preclosure-check_${JOB}.out"
ERR="$ROOT/closure_20260810/logs/N22-preclosure-check_${JOB}.err"
RECEIPT="$ROOT/closure_20260810/provenance/preclosure_payload_seq94_receipt.json"
JOB_RECEIPT="$ROOT/closure_20260810/provenance/preclosure_validation_seq94_job.txt"

echo "=== VALIDATION STATE ==="
squeue -h -j "$JOB" -o '%i|%T|%r|%j' || true
sacct -n -P -j "$JOB" --format=JobID,JobName,State,ExitCode,Elapsed,Start,End | sed '/^[[:space:]]*$/d'

STATE=$(sacct -n -P -j "$JOB" --format=JobIDRaw,State | awk -F'|' -v job="$JOB" '$1 == job {print $2; exit}')
echo "validation_state=$STATE"
if [ "$STATE" = "COMPLETED" ]; then
  test -f "$OUT"
  test -f "$ERR"
  echo "=== VALIDATION STDOUT ==="
  cat "$OUT"
  echo "=== VALIDATION STDERR ==="
  cat "$ERR"
  test ! -s "$ERR"
  grep -q '63 passed' "$OUT"
  grep -q 'finished=' "$OUT"
  sha256sum "$OUT" "$ERR" "$RECEIPT" "$JOB_RECEIPT"
elif [ "$STATE" = "RUNNING" ] || [ "$STATE" = "PENDING" ]; then
  echo "validation_pending=1"
else
  echo "Unexpected validation state: $STATE" >&2
  exit 4
fi

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
