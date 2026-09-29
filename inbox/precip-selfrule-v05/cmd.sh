#!/bin/bash
# precip-selfrule-v05 seq=9: read-only progress for the eight-basin technical array.
set -o pipefail
ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_20260929_r03
OUT="$ROOT/technical_8/run01"

date "+wallclock %F %T %z"
echo "=== SQUEUE ==="
squeue -j 231259 -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true
echo "=== SACCT ==="
sacct -j 231259 --format=JobID,JobName%24,State,ExitCode,Elapsed,AllocTRES%40,MaxRSS,NodeList%14 -P || true
echo "=== FIT RECORD COUNT ==="
if test -d "$OUT/fit"; then
  find "$OUT/fit" -maxdepth 1 -type f -name '*.json' -printf '%f\n' | sort
  printf 'COUNT='
  find "$OUT/fit" -maxdepth 1 -type f -name '*.json' | wc -l
else
  echo FIT_DIR_PENDING
fi
echo "=== TECHNICAL LOG TAILS ==="
for f in "$ROOT"/logs/technical-231259_*.out "$ROOT"/logs/technical-231259_*.err; do
  test -e "$f" || continue
  echo "--- $f"
  tail -20 "$f"
done