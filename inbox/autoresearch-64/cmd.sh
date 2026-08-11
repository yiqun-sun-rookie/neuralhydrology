#!/bin/bash
set -o pipefail

ROOT=/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/hbv_lite_64_prospective_confirmation_20260811_seq62

echo "=== JOB 202557 ==="
squeue -j 202557 -o '%.18i %.20j %.12T %.10M %.10l %.20R'
sacct -j 202557 -X --format=JobID%12,JobName%20,NodeList%9,State%14,ExitCode%8,Elapsed%10,Start%20,End%20

echo "=== EVIDENCE STATUS ==="
for path in \
  "$ROOT/evidence/PROMOTION_RECEIPT.json" \
  "$ROOT/evidence/TARGETED_GATE.json" \
  "$ROOT/evidence/FULL_GATE.json" \
  "$ROOT/evidence/PACKAGE_GATE.json" \
  "$ROOT/candidate_run/CANDIDATE_SUMMARY.json" \
  "$ROOT/evidence/REPRODUCTION_SUMMARY.json" \
  "$ROOT/evidence/PROMOTION_TIMING.json" \
  "$ROOT/evidence/MANIFEST.sha256"; do
  if [ -e "$path" ]; then
    stat -c 'EXISTS %n bytes=%s mtime=%y' "$path"
  else
    echo "PENDING $path"
  fi
done

echo "=== LOG TAILS ==="
for path in "$ROOT/evidence/JOB_STDOUT.txt" "$ROOT/evidence/JOB_STDERR.txt"; do
  if [ -f "$path" ]; then
    echo "--- $path"
    tail -30 "$path"
  fi
done
