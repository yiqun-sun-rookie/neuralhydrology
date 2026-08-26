#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
echo "=== STATE ==="
for j in 212919 212920; do sacct -j "$j" -X --format=JobID%9,JobName%9,NodeList%8,State%12,ExitCode%7,Elapsed%9 2>&1 | tail -1; done
echo "=== VERDICTS ==="
for j in 212919 212920; do
  echo "  ======== job $j ========"
  if [ -f "$ROOT/probe/equiv_${j}.out" ]; then tail -40 "$ROOT/probe/equiv_${j}.out" | sed 's/^/    /'; else echo "    (no stdout yet)"; fi
  if [ -s "$ROOT/probe/equiv_${j}.err" ]; then echo "    -- err --"; tail -8 "$ROOT/probe/equiv_${j}.err" | sed 's/^/      /'; fi
done
echo "=== SCRATCH DIRS PRESENT ==="
ls -d "$ROOT"/equiv_scratch_* 2>/dev/null | head -5 || echo "  none"
echo "=== DONE ==="
