#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
echo "=== STAMP ==="; date -Iseconds
echo "=== A. JOB STATES ==="
sacct -j 223971,223972,223973 -X --format=JobID%10,JobName%16,State%14,ExitCode%8,Elapsed%10,NodeList%8 2>&1 || true
echo "=== B. RESCORE OUTPUT ==="
F=$(ls -t "$ROOT"/logs/33_transformer_recipe_repair/rescore-*.out 2>/dev/null | head -1)
echo "log: $F"
cat "$F" 2>&1 | head -60 || echo "  no log yet"
echo "-- stderr tail --"
E=$(ls -t "$ROOT"/logs/33_transformer_recipe_repair/rescore-*.err 2>/dev/null | head -1)
tail -n 20 "$E" 2>&1 || true
echo "=== C. REPRO PROGRESS ==="
for J in 223971 223972; do
  echo "-- $J --"
  tail -n 6 "$ROOT/logs/33_transformer_recipe_repair/repro-${J}.out" 2>&1 || true
  grep -hoE 'Epoch [0-9]+ average loss[^|]*' "$ROOT"/logs/33_transformer_recipe_repair/repro-${J}-r*.log 2>/dev/null | tail -6 || true
done
