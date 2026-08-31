#!/bin/bash
# Read-only progress check on array 216811, plus selection scores of any finished run.
set -o pipefail
ROOT=$HOME/kuwei_jdl_seedbatch_20260831
RUNS=$ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/kuwei_joint_da_learning_20260826/runs
echo "=== A. state counts ==="
sacct -j 216811 -X --format=State%20 --noheader 2>&1 | sort | uniq -c || true
echo "=== B. per-task ==="
sacct -j 216811 -X --format=JobID%16,State%12,Elapsed%10 --noheader 2>&1 | head -20 || true
echo "=== C. finished run dirs ==="
ls $RUNS 2>&1 | head -20 || true
echo "=== D. selection scores of finished runs ==="
for d in $RUNS/*/; do
  m=$d/run_manifest.json
  if [ -f "$m" ]; then
    python -c "
import json,sys
d=json.load(open('$m'))
print('%-28s arm=%-12s ls=%-2s best_update=%-4s best_selection_mse=%.6f  elapsed=%.0fs' % (
  '$(basename $d)', d['arm_id'], d.get('learning_seed','?'), d['best_update'],
  d['best_selection_mse'], d['elapsed_seconds']))
" 2>&1
  fi
done | head -20 || true
echo "=== E. failures ==="
for f in $ROOT/logs/kuwei-jdl-s1-216811_*.err; do
  if [ -s "$f" ]; then echo "--- $f ---"; tail -4 "$f"; fi
done 2>&1 | head -20 || true
echo "=== DONE ==="
