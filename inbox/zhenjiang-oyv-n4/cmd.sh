#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
echo "=== WAIT FOR THE TWO A800 PROBES (max 12 min) ==="
for i in $(seq 1 72); do
  LEFT=0
  for j in 212950 212951; do
    st=$(sacct -j "$j" -X -n -o State 2>/dev/null | head -1 | awk '{print $1}')
    case "$st" in RUNNING|PENDING|"") LEFT=$((LEFT+1));; esac
  done
  [ "$LEFT" -eq 0 ] && { echo "  settled t=$((i*10))s"; break; }
  sleep 10
done
echo "=== STATE ==="
for j in 212950 212951; do sacct -j "$j" -X --format=JobID%9,JobName%8,NodeList%8,State%11,ExitCode%7,Elapsed%9 2>&1 | tail -1; done
echo "=== RESULTS ==="
for j in 212950 212951; do
  echo "  ============ $j ============"
  [ -f "$ROOT/probe/platform_${j}.out" ] && sed -n '1,200p' "$ROOT/probe/platform_${j}.out" | sed 's/^/    /' || echo "    none"
  [ -s "$ROOT/probe/platform_${j}.err" ] && { echo "  -- err --"; tail -8 "$ROOT/probe/platform_${j}.err" | sed 's/^/      /'; }
done
echo "=== n4 PROGRESS ==="
echo "  n4_tasks: $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l) / 1440"
echo "=== DONE ==="
