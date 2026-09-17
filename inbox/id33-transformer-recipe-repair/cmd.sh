#!/bin/bash
# seq=70 AUDIT-2: training-set size (iterations per epoch) and per-epoch training loss for G1 vs C4 (overfitting signature), login-node grep only.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date -Iseconds
for a in G1 G1_s200 G1_s300 G1_s400 G1_s500 G1_s600 G1_s700 G1_s800 C4 C4_s200 C4_s300 C4_s400 C4_s500 C4_s600 C4_s700 C4_s800; do
  d=$(ls -d results/33_transformer_recipe_repair/$a/*_2026_* 2>/dev/null | tail -1)
  log=$(ls "$d"/output.log 2>/dev/null | head -1)
  echo "##ARM $a log=$log"
  [ -n "$log" ] || continue
  echo "  samples/iters: $(grep -o -m1 '[0-9]\+ basins\|[0-9]\+/[0-9]\+ \[' "$log" | head -2 | tr '\n' ' ') $(grep -o 'Epoch 1: 100%[^]]*' "$log" | head -1 | grep -o '[0-9]\+/[0-9]\+' | head -1)"
  echo "  avg loss by epoch: $(grep -o 'Epoch [0-9]\+ average loss: [0-9.e+-]\+' "$log" | sed 's/Epoch \([0-9]*\) average loss: /\1=/' | tr '\n' ' ')"
  echo "  val by epoch: $(grep -o 'Epoch [0-9]\+ average validation loss: [0-9.e+-]\+ -- Median validation metrics: NSE: [0-9.-]\+' "$log" | sed 's/Epoch \([0-9]*\) average validation loss: \([0-9.e+-]*\) -- Median validation metrics: NSE: /\1=\2|/' | tr '\n' ' ')"
done
echo "=== DONE ==="
