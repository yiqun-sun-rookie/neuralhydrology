#!/bin/bash
# OWN jobs only. E0-fp32 tasks (246243_5..9, DA epochs=0, forward only; est ~25 min each, cf. P1b noda 2:39 per 100 basins
# x ~8.7 full-period factor) keep a 6h limit that blocks backfill on the idle ngu001. Lower just these to 1:30:00 (the limit
# that backfilled the P1b grid on ngu001/ngu007). Limits can only go down; E1/E1default (~3.2 h) keep 6h.
set -o pipefail
date --iso-8601=seconds
for T in 5 6 7 8 9; do
  st=$(squeue -j 246243_$T -h -o '%T' 2>/dev/null | head -1)
  echo "246243_$T state=${st:-GONE}"
  [ "$st" = PENDING ] && scontrol update jobid=246243_$T TimeLimit=1:30:00 2>&1 && echo "  -> TimeLimit=1:30:00"
done
sleep 45
echo "=== AFTER ==="
squeue -u $USER -h -o '%i|%T|%l|%P|%R|%S|%N' 2>&1 | grep -E '^2462(43|78|79|80|81)' | head -16
echo "SEQ26_DONE"
