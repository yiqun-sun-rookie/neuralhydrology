#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf23_20260826
echo "=== JOB STATE ==="
sacct -j 212954 -X --format=JobID%12,State%14,ExitCode%8,Elapsed%10,NodeList%10 2>&1 | head -5
echo "=== ANCHOR RESULTS ==="
ls $ROOT/results/anchor/ 2>/dev/null | wc -l
for f in $ROOT/results/anchor/*.json; do
  [ -e "$f" ] || continue
  b=$(basename $f .json)
  d=$(grep -o '"anchor_delta": [0-9.e+-]*' $f | cut -d' ' -f2)
  p=$(grep -o '"passed": [a-z]*' $f | cut -d' ' -f2)
  echo "$b delta=$d passed=$p"
done
echo "=== JOB LOG TAIL ==="
tail -6 $ROOT/logs/tukf23_anchor_212954_*.out 2>/dev/null || tail -6 $ROOT/logs/tukf23_anchor_*.out 2>/dev/null || echo "no log yet"
tail -4 $ROOT/logs/tukf23_anchor_212954_*.err 2>/dev/null || tail -4 $ROOT/logs/tukf23_anchor_*.err 2>/dev/null || true
