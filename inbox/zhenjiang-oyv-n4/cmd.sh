#!/bin/bash
# How many RTX 3090 cards are actually free, and what is blocking my tasks?
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. PER-NODE GPU ALLOCATION (the 3090 nodes) ==="
printf "  %-8s %-11s %-10s %-40s\n" NODE STATE CFG ALLOC
for n in ngu001 ngu004 ngu005 ngu006 ngu007 ngu008 ngu010 ngu011 ngu003 ngu009; do
  info=$(scontrol show node "$n" 2>/dev/null)
  st=$(echo "$info" | grep -oE 'State=[A-Z+]*' | head -1 | cut -d= -f2)
  cfg=$(echo "$info" | grep -oE 'CfgTRES=[^ ]*' | head -1 | cut -d= -f2)
  alloc=$(echo "$info" | grep -oE 'AllocTRES=[^ ]*' | head -1 | cut -d= -f2)
  printf "  %-8s %-11s %-10s %-40s\n" "$n" "${st:-?}" "${cfg:-?}" "${alloc:-none}"
done

echo "=== B. WHY IS MY ARRAY NOT STARTING MORE TASKS ==="
for j in 212932 212933; do
  echo "  ---- $j ----"
  squeue -j "$j" -h -o "  %.20i %.9T %.20r %.20S" 2>/dev/null | head -3 || true
done

echo "=== C. GPU TRES ACROSS THE TWO PARTITIONS ==="
sinfo -p hgpu2p,hgpu2 -N -o "%.9N %.9P %.11T %.5C %.12G" 2>&1 || true
echo "  legend for %C is allocated/idle/other/total cpus"

echo "=== D. HOW MANY OF MY TASKS ARE RUNNING, AND WHERE ==="
squeue -u "$USER" -h -t RUNNING -o "%.20i %.12j %.10P %.10N" 2>/dev/null || true

echo "=== E. THROUGHPUT SO FAR ==="
echo "  n4_tasks: $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l) / 1440"
sacct -j 212932 -X -n -P -o State 2>/dev/null | sort | uniq -c | sed 's/^/    212932 /'
sacct -j 212933 -X -n -P -o State 2>/dev/null | sort | uniq -c | sed 's/^/    212933 /'

echo "=== F. IDLE CAPACITY ON THE OTHER PARTITIONS (for reference only) ==="
sinfo -p hgpu4,hgpu8 -N -o "%.9N %.9P %.11T %.5C %.12G" 2>&1 || true
echo "=== DONE ==="
