#!/bin/bash
# seq=41 batch-3 progress check (read only)
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo

echo "=== STAMP ==="; date -Iseconds

echo "=== A. SACCT ==="
sacct -j 224310,224311,224312 -X -o JobID,JobName%18,State,ExitCode,Elapsed,NodeList 2>&1 | head -20

echo "=== B. QUEUE ==="
squeue -u "$USER" -o "%.10i %.18j %.2t %.10M %.8R" 2>&1 | head -20

echo "=== C. PER-ARM EPOCH PROGRESS ==="
cd "$ROOT" || exit 1
for f in $(ls -1 results/33_transformer_recipe_repair/*/*/output.log 2>/dev/null | tail -12); do
  echo "-- $f"
  grep -c 'Epoch' "$f" 2>/dev/null || echo 0
  grep 'Median validation metrics' "$f" 2>/dev/null | tail -2 || true
done

echo "=== D. UTILISATION FILES ==="
ls -la logs/33_transformer_recipe_repair/utilisation-2243*.csv 2>&1 | head -5
for u in logs/33_transformer_recipe_repair/utilisation-2243*.csv; do
  [ -f "$u" ] || continue
  echo "-- $u lines=$(wc -l < "$u")"
  tail -3 "$u" 2>/dev/null || true
done

echo "=== E. ERR TAILS ==="
for e in $(ls -1t logs/33_transformer_recipe_repair/*2243*.err 2>/dev/null | head -3); do
  echo "-- $e"; tail -8 "$e" 2>/dev/null || true
done
