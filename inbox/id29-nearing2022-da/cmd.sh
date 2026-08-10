#!/bin/bash
# ID29 seq=96: diagnose failed preclosure validation job 202365 without modifying or resubmitting anything.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOB=202365
OUT="$ROOT/closure_20260810/logs/N22-preclosure-check_${JOB}.out"
ERR="$ROOT/closure_20260810/logs/N22-preclosure-check_${JOB}.err"
RECEIPT="$ROOT/closure_20260810/provenance/preclosure_payload_seq94_receipt.json"
JOB_RECEIPT="$ROOT/closure_20260810/provenance/preclosure_validation_seq94_job.txt"

echo "=== FAILED JOB ACCOUNTING ==="
sacct -n -P -j "$JOB" --format=JobID,JobName,State,ExitCode,Elapsed,Start,End,NodeList | sed '/^[[:space:]]*$/d'
STATE=$(sacct -n -P -j "$JOB" --format=JobIDRaw,State | awk -F'|' -v job="$JOB" '$1 == job {print $2; exit}')
test "$STATE" = "FAILED"

echo "=== STDOUT ==="
test -f "$OUT"
cat "$OUT"
echo "=== STDERR ==="
test -f "$ERR"
cat "$ERR"

echo "=== IMMUTABLE DIAGNOSTIC HASHES ==="
sha256sum "$OUT" "$ERR" "$RECEIPT" "$JOB_RECEIPT"

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
