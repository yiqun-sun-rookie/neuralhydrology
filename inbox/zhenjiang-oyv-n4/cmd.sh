#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
echo "=== WHY DID THEY FAIL ==="
for j in 212942 212943; do
  echo "  ==== $j ===="
  sacct -j "$j" --format=JobID%12,State%12,ExitCode%9,Elapsed%9,NodeList%9 2>&1 | head -4
  echo "  -- stdout --"; [ -f "$ROOT/probe/platform_${j}.out" ] && tail -25 "$ROOT/probe/platform_${j}.out" | sed 's/^/    /' || echo "    (none)"
  echo "  -- stderr --"; [ -f "$ROOT/probe/platform_${j}.err" ] && tail -25 "$ROOT/probe/platform_${j}.err" | sed 's/^/    /' || echo "    (none)"
done
echo "=== REFERENCE TASK NAMES PRESENT? ==="
ls -1 "$ROOT/ladder_tasks" 2>/dev/null | head -5
echo "  count: $(ls -1 "$ROOT/ladder_tasks" 2>/dev/null | wc -l)"
echo "  looking for the twelve:"
for t in zhenjiang_ladder_v2__fold_2017__zhenjiang__complete_observation__seed_17 \
         zhenjiang_ladder_v2__fold_2017__zhenjiang__hidden_target_minus_nanjing__seed_17 \
         zhenjiang_ladder_v2__fold_2017__jiangyin__hidden_target_minus_xuliujing__seed_17; do
  [ -f "$ROOT/ladder_tasks/$t/test_predictions.npz" ] && echo "    ok  $t" || echo "    MISSING $t"
done
echo "=== n4 PROGRESS ==="
echo "  n4_tasks: $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l) / 1440"
squeue -u "$USER" -h -o "%.20i %.12j %.9T" 2>/dev/null | grep zj_oyv || true
echo "=== DONE ==="
