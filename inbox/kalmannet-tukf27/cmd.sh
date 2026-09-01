#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf27_20260901
echo "=== ANCHOR JOB 217684 ==="
sacct -j 217684 -X -n -P --format=State,ExitCode,Elapsed 2>/dev/null || true
STATE=$(sacct -j 217684 -X -n -P --format=State 2>/dev/null | head -1)
[ "$STATE" = "COMPLETED" ] || { echo "NOT_DONE state=$STATE"; tail -3 $ROOT/logs/tukf27_anchor_*.out 2>/dev/null; exit 0; }
python3 -c "
import json
v=json.load(open('$ROOT/results/anchor_gate_verdict.json'))
print('anchor pass:',v['pass'],v['passed_count'],'/',v['required'])
import glob
print('prior_sim records:', len(glob.glob('$ROOT/results/prior_sim/*.json')))
"
echo "=== SBATCH TRAIN ARRAY 108 ==="
if squeue -u $USER -h -o "%j" 2>/dev/null | grep -q tukf27_train; then echo QUEUED_ALREADY
else
  out=$(sbatch $ROOT/slurm/tukf27_train.slurm 2>&1); echo "$out"
  echo "$out" | grep -qE 'Submitted batch job [0-9]+' || { echo "SUBMIT_FAILED"; exit 1; }
fi
echo "SEQ2_OK"
