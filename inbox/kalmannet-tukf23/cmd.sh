#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf23_20260826
echo "=== ARRAY STATE ==="
sacct -j 213028 -X -n --format=State%14 2>&1 | sort | uniq -c
echo "=== TRAIN RECORDS DONE ==="
ls $ROOT/results/train/ 2>/dev/null | wc -l
ls $ROOT/results/train/ 2>/dev/null | sed 's/^[0-9]*_//;s/\.json//' | sort | uniq -c
echo "=== SAMPLE COMPLETED ==="
for f in $(ls $ROOT/results/train/*.json 2>/dev/null | head -3); do
  b=$(basename $f .json)
  u=$(grep -o '"selected_update": [0-9]*' $f | cut -d' ' -f2)
  s=$(grep -o '"seconds": [0-9.]*' $f | cut -d' ' -f2)
  echo "$b selected=$u seconds=$s"
done
echo "=== FAILURES ==="
sacct -j 213028 -X -n -P --format=JobID,State,ExitCode 2>&1 | grep -E 'FAILED|TIMEOUT|OUT_OF_MEM|NODE_FAIL' || echo none
grep -l Traceback $ROOT/logs/tukf23_train_*.err 2>/dev/null | head -5 || true
