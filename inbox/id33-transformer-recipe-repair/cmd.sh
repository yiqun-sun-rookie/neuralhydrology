#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
echo "=== STAMP ==="; date -Is
echo "=== A. SACCT CALIBRATION ==="
sacct -j 220658,220659 -X --format=JobID,JobName%14,State,ExitCode,Elapsed,NodeList 2>&1 || true
cd $ROOT || exit 1
echo "=== B. C1/C2 LOG LOCATION ==="
find results/33_transformer_recipe_repair -maxdepth 4 -name 'output.log' -newermt '2026-09-04' 2>/dev/null | head -10 || true
ls -1d results/33_transformer_recipe_repair/_invocations/*C1* results/33_transformer_recipe_repair/_invocations/*C2* 2>/dev/null | head -10 || true
echo "=== C. SLURM LOGS ==="
for J in 220658 220659; do
  echo "--- job $J"
  f=$(find . logs -maxdepth 4 -name "*${J}*" -type f 2>/dev/null | head -4)
  echo "$f"
done
echo "=== D. C1/C2 EPOCH DIRS ==="
for A in C1 C2; do
  echo "--- $A"
  ls -1d results/33_transformer_recipe_repair/$A/*/validation/model_epoch0* 2>/dev/null | tail -3 || true
done
echo "ID33_WATCH_COMPLETE"
