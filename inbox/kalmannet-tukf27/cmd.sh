#!/bin/bash
set -o pipefail
echo "=== TUKF25/26/27 JOB FINAL STATES ==="
for j in 216699 216851 217266 217271 217272 217426 217684 217690 217822; do
  s=$(sacct -j $j -X -n -P --format=State 2>/dev/null | head -1)
  echo "  job $j : ${s:-unknown}"
done
echo "=== MY RUNNING/PENDING JOBS ==="
squeue -u $USER -h -o "%i %j %T" 2>/dev/null | head -20 || true
echo "=== LANDING DIRS ==="
for d in kalmannet_tukf25_20260831 kalmannet_tukf26_20260831 kalmannet_tukf27_20260901; do
  p=/data1/home/sunyiq/$d
  [ -d "$p" ] && echo "  $d: exists, $(du -sh $p 2>/dev/null | cut -f1)" || echo "  $d: MISSING"
done
echo "DONE"
