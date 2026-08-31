#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf25_20260831
echo "=== PRECONDITION ==="
python3 -c "
import json
v = json.load(open('$ROOT/results/anchor_gate_verdict.json'))
assert v['pass'] and v['passed_count'] == 27, 'anchor gate not green'
print('anchor gate green 27/27')
"
[ $? -eq 0 ] || { echo "PRECONDITION_FAILED"; exit 1; }
echo "=== SBATCH TRAIN ARRAY 108 ==="
out=$(sbatch $ROOT/slurm/tukf25_train.slurm 2>&1); echo "$out"
echo "$out" | grep -qE 'Submitted batch job [0-9]+' || { echo "SUBMIT_FAILED"; exit 1; }
JID=$(echo "$out" | grep -oE '[0-9]+' | head -1)
echo "train_job_id=$JID"
echo "=== QUEUE SNAPSHOT ==="
squeue -u $USER 2>/dev/null | grep -E "tukf25|JOBID" | head -8 || true
echo "SEQ3_OK"
