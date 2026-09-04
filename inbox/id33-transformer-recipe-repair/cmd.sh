#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
echo "=== STAMP ==="; date -Is
echo "=== A. SACCT SIX ARMS + CALIBRATION ==="
sacct -j 220490,220491,220492,220493,220494,220495,220658,220659 -X --format=JobID,JobName%14,State,ExitCode,Elapsed,NodeList 2>&1 || true
cd $ROOT || exit 1
echo "=== B. C1/C2 LAST EPOCH LINES ==="
for A in C1 C2; do
  echo "--- $A"
  f=$(ls -1t results/33_transformer_recipe_repair/_invocations/id33_${A}_s*/output.log 2>/dev/null | head -1)
  echo "log=$f"
  [ -n "$f" ] && tail -c 300000 "$f" | grep -E 'Median validation metrics' | tail -3 || true
done
echo "=== C. C1/C2 EPOCH30 FILE PRESENCE ==="
for A in C1 C2; do
  g=$(ls -1 results/33_transformer_recipe_repair/$A/*/validation/model_epoch030/validation_metrics.csv 2>/dev/null | head -1)
  echo "$A epoch30=$g"
done
echo "ID33_WATCH_COMPLETE"
