#!/bin/bash
# seq=68 pull G1 x8 per-basin epoch-30 validation tables (seq=67 ran the wrong script; my push bug).
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date -Iseconds
for a in G1 G1_s200 G1_s300 G1_s400 G1_s500 G1_s600 G1_s700 G1_s800; do
  d=$(ls -d results/33_transformer_recipe_repair/$a/*_2026_09* 2>/dev/null | tail -1)
  f="$d/validation/model_epoch030/validation_metrics.csv"
  [ -f "$f" ] || { echo "##ARM $a NOFILE"; continue; }
  echo "##ARM $a"; tail -n +2 "$f"
done
echo "=== DONE ==="
