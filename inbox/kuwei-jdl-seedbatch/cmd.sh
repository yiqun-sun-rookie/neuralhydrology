#!/bin/bash
# Read-only progress check on array job 216811.
set -o pipefail
ROOT=$HOME/kuwei_jdl_seedbatch_20260831
RUNS=$ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/kuwei_joint_da_learning_20260826/runs
echo "=== A. state counts ==="
sacct -j 216811 -X --format=State%20 --noheader 2>&1 | sort | uniq -c || true
echo "=== B. per-task ==="
sacct -j 216811 -X --format=JobID%16,State%12,Elapsed%10 --noheader 2>&1 | head -20 || true
echo "=== C. run dirs ==="
ls $RUNS 2>&1 | head -20 || true
echo "=== D. manifests ==="
ls $RUNS/*/run_manifest.json 2>/dev/null | wc -l || true
echo "=== E. progress of task 1 ==="
tail -3 $ROOT/logs/kuwei-jdl-s1-216811_1.out 2>&1 || true
echo "=== F. failures ==="
for f in $ROOT/logs/kuwei-jdl-s1-216811_*.err; do
  if [ -s "$f" ]; then echo "--- $f ---"; tail -4 "$f"; fi
done 2>&1 | head -20 || true
echo "=== DONE ==="
