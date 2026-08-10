#!/bin/bash
# ID29 seq=99: inspect replacement no-pytest preclosure validation job 202369 and preserve its exact logs.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOB=202369
OUT="$ROOT/closure_20260810/logs/N22-preclosure-check_${JOB}.out"
ERR="$ROOT/closure_20260810/logs/N22-preclosure-check_${JOB}.err"
DEPLOYMENT_RECEIPT="$ROOT/closure_20260810/provenance/preclosure_payload_seq98_receipt.json"
JOB_RECEIPT="$ROOT/closure_20260810/provenance/preclosure_validation_seq98_job.txt"

echo "=== VALIDATION STATE ==="
squeue -h -j "$JOB" -o '%i|%T|%r|%j' || true
sacct -n -P -j "$JOB" --format=JobID,JobName,State,ExitCode,Elapsed,Start,End,NodeList | sed '/^[[:space:]]*$/d'
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
  grep -q '"ok": true' "$OUT"
  grep -q '"tests": 64' "$OUT"
  grep -q '"unique_file_count": 97' "$OUT"
  grep -q '"file_count": 20' "$OUT"
  grep -q '"dataset_sha256": "a3cb1f81e6b2f25e2b919c0d5b315e46fe82f8ed9c9d8a4bd56671da5500a35f"' "$OUT"
  grep -q 'finished=' "$OUT"
  sha256sum "$OUT" "$ERR" "$DEPLOYMENT_RECEIPT" "$JOB_RECEIPT"
elif [ "$STATE" = "RUNNING" ] || [ "$STATE" = "PENDING" ]; then
  echo "validation_pending=1"
else
  echo "=== FAILED STDOUT ==="
  test -f "$OUT" && cat "$OUT"
  echo "=== FAILED STDERR ==="
  test -f "$ERR" && cat "$ERR"
  test -f "$OUT" && test -f "$ERR" && sha256sum "$OUT" "$ERR" "$DEPLOYMENT_RECEIPT" "$JOB_RECEIPT"
fi

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"

if [ "$STATE" != "COMPLETED" ] && [ "$STATE" != "RUNNING" ] && [ "$STATE" != "PENDING" ]; then
  exit 4
fi
