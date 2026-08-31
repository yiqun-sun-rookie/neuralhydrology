#!/bin/bash
# Read-only progress check on array job 216811. No submission, no waiting loops.
set -o pipefail
ROOT=$HOME/kuwei_jdl_seedbatch_20260831
RUNS=$ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/kuwei_joint_da_learning_20260826/runs
echo "=== A. array state counts ==="
sacct -j 216811 -X --format=State%20 --noheader 2>&1 | sort | uniq -c || true
echo "=== B. per-task elapsed (completed only) ==="
sacct -j 216811 -X --format=JobID%16,State%12,Elapsed%10 --noheader 2>&1 | head -20 || true
echo "=== C. still queued/running ==="
squeue -u ${USER} -n kuwei-jdl-s1 -o "%.14i %.12T %R" 2>&1 | head -8 || true
echo "=== D. finished run directories ==="
ls $RUNS 2>&1 | head -20 || true
echo "=== E. manifests written ==="
ls $RUNS/*/run_manifest.json 2>/dev/null | wc -l || true
echo "=== F. any failed task stderr ==="
for f in $ROOT/logs/kuwei-jdl-s1-216811_*.err; do
  if [ -s "$f" ]; then echo "--- $f ---"; tail -4 "$f"; fi
done 2>&1 | head -30 || true
echo "=== DONE ==="
