#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
echo "=== WAIT FOR THE TWO EQUIVALENCE JOBS (max 15 min) ==="
for i in $(seq 1 90); do
  LEFT=0
  for j in 212919 212920; do
    st=$(sacct -j "$j" -X -n -o State 2>/dev/null | head -1 | awk '{print $1}')
    case "$st" in RUNNING|PENDING|"") LEFT=$((LEFT+1));; esac
  done
  [ "$LEFT" -eq 0 ] && { echo "  settled t=$((i*10))s"; break; }
  sleep 10
done
echo "=== STATE ==="
for j in 212919 212920; do sacct -j "$j" -X --format=JobID%9,JobName%9,NodeList%8,State%12,ExitCode%7,Elapsed%9 2>&1 | tail -1; done
echo "=== VERDICTS ==="
for j in 212919 212920; do
  echo "  ======== job $j ========"
  if [ -f "$ROOT/probe/equiv_${j}.out" ]; then tail -45 "$ROOT/probe/equiv_${j}.out" | sed 's/^/    /'; else echo "    (no stdout)"; fi
  if [ -s "$ROOT/probe/equiv_${j}.err" ]; then echo "    -- err tail --"; tail -8 "$ROOT/probe/equiv_${j}.err" | sed 's/^/      /'; fi
done
echo "=== DONE ==="
