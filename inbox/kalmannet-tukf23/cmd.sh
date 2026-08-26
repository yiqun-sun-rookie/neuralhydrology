#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf23_20260826
echo "=== SUBMIT FORMAL TRAIN ARRAY (108 cells) ==="
out=$(sbatch --array=0-107 $ROOT/slurm/tukf23_train.slurm 2>&1); echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$JID" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "train_array_job=$JID"
sleep 20
echo "=== FIRST LOOK ==="
sacct -j $JID -X --format=JobID%16,State%12 2>&1 | awk '{print $2}' | sort | uniq -c | head -8
squeue -u $USER -h -o "%i %t %r" 2>&1 | grep -c "^$JID" || true
