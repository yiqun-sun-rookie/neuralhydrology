#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
for j in 212946 212947; do
  echo "  ======== $j ========"
  sacct -j "$j" --format=JobID%12,State%12,ExitCode%9,Elapsed%9 2>&1 | head -4
  echo "  -- stdout (full) --"
  [ -f "$ROOT/probe/platform_${j}.out" ] && cat "$ROOT/probe/platform_${j}.out" | tail -40 | sed 's/^/    /' || echo "    none"
  echo "  -- stderr (full) --"
  [ -f "$ROOT/probe/platform_${j}.err" ] && cat "$ROOT/probe/platform_${j}.err" | tail -40 | sed 's/^/    /' || echo "    none"
done
echo "=== n4 ==="
echo "  n4_tasks: $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l) / 1440"
echo "=== DONE ==="
