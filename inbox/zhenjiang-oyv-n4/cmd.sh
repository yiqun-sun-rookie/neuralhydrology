#!/bin/bash
# Open the throttle: fill every RTX 3090 the scheduler will give us.
#
# The cap of eight per half was politeness, not a requirement. The two 3090
# partitions hold twenty cards in total, so the throttle is lifted to twenty per
# half and the scheduler decides what actually fits. A800 and A40 stay excluded,
# not because they are busy or oversized but because a different card model
# produces different numbers, and the other half of this experiment already ran
# on 3090.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. BEFORE ==="
squeue -u "$USER" -h -o "%.20i %.12j %.14P %.9T" 2>/dev/null | grep zj_oyv_n4 || true
echo "  my running: $(squeue -u "$USER" -h -t RUNNING -o '%i' 2>/dev/null | wc -l)"
echo "  n4_tasks  : $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l) / 1440"

echo "=== B. RAISE THE ARRAY THROTTLE ==="
for j in 212932 212933; do
  out=$(scontrol update JobId="$j" ArrayTaskThrottle=20 2>&1)
  if [ -z "$out" ]; then echo "  $j throttle -> 20"; else echo "  $j: $out"; fi
done

echo "=== C. 3090 CAPACITY RIGHT NOW ==="
sinfo -p hgpu2p,hgpu2 -o "%.10P %.8N %.10T %.10G" 2>&1 | head -14 || true
echo "  --- per-node free gpus (alloc/total) ---"
scontrol show node ngu001 ngu004 ngu005 ngu006 ngu007 ngu008 ngu009 ngu010 ngu011 ngu003 2>/dev/null \
  | grep -E 'NodeName=|AllocTRES=|State=' | paste - - - 2>/dev/null | sed 's/^/    /' | head -12 || true

echo "=== D. AFTER (give the scheduler a moment) ==="
sleep 45
squeue -u "$USER" -h -o "%.20i %.12j %.14P %.9T" 2>/dev/null | grep zj_oyv_n4 || true
echo "  my running: $(squeue -u "$USER" -h -t RUNNING -o '%i' 2>/dev/null | wc -l)"
echo "  n4_tasks  : $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l) / 1440"
echo "  nodes in use by me:"
squeue -u "$USER" -h -t RUNNING -o "%N" 2>/dev/null | tr ',' '\n' | sort | uniq -c | sed 's/^/    /' || true
echo "=== DONE ==="
