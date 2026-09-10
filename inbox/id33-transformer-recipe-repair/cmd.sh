#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date +%FT%T%z
echo "=== EPOCHWISE MEDIANS ==="
for a in T1 T2 T3 T4 T5 L33 C3 C4 C5; do
  d=$(ls -d results/33_transformer_recipe_repair/$a/*_2026_09[01]* 2>/dev/null | tail -1)
  [ -n "$d" ] || { echo "###EPOCHS $a NONE"; continue; }
  echo "###EPOCHS $a $d"
  grep 'Median validation metrics' "$d/output.log" 2>/dev/null | sed -E 's/.*Epoch ([0-9]+) .*NSE: ([0-9.\-]+).*/\1,\2/' || true
done
echo "=== PERBASIN ARMS ==="
for a in T1 T2 T3 T4 T5 L33 C3 C4 C5; do
  d=$(ls -d results/33_transformer_recipe_repair/$a/*_2026_09[01]* 2>/dev/null | tail -1)
  f="$d/validation/model_epoch030/validation_metrics.csv"
  [ -f "$f" ] || { echo "###ARM $a NOFILE"; continue; }
  echo "###ARM $a rows=$(wc -l < "$f")"
  cat "$f"
done
echo "=== PERBASIN BASELINES (read-only ID30) ==="
ID30=/data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo/results/30_modern_transformer_moe
for a in D01 B01; do
  f=$(ls "$ID30"/$a/*/validation/model_epoch030/validation_metrics.csv 2>/dev/null | tail -1)
  [ -n "$f" ] || { echo "###BASE $a NOFILE"; continue; }
  echo "###BASE $a rows=$(wc -l < "$f") src=$f"
  cat "$f"
done
echo "=== DONE ==="
