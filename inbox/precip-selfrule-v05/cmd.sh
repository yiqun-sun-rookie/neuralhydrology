#!/bin/bash
# precip-selfrule-v05 seq=8: read-only status after gated retry submission.
set -o pipefail
ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_20260929_r03
OUT="$ROOT/technical_8/run01"

date "+wallclock %F %T %z"
hostname
echo "=== SQUEUE ==="
squeue -j 231258,231259 -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true
echo "=== SACCT ==="
sacct -j 231258,231259 --format=JobID,JobName%24,State,ExitCode,Elapsed,AllocTRES%40,MaxRSS,NodeList%14 -P || true
echo "=== RUNTIME JSON ==="
if test -f "$OUT/runtime_validation.json"; then cat "$OUT/runtime_validation.json"; else echo RUNTIME_JSON_PENDING; fi
echo "=== RUNTIME LOG ==="
for f in "$ROOT"/logs/runtime-231258.out "$ROOT"/logs/runtime-231258.err; do
  echo "--- $f"
  if test -f "$f"; then tail -80 "$f"; else echo MISSING; fi
done
echo "=== FIT RECORDS ==="
if test -d "$OUT/fit"; then find "$OUT/fit" -maxdepth 1 -type f -name '*.json' -printf '%f\n' | sort; else echo FIT_DIR_PENDING; fi