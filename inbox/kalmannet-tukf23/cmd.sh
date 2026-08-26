#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf23_20260826
echo "=== ANCHOR V2 STATE ==="
sacct -j 213212 -X --format=JobID%10,State%12,ExitCode%8,Elapsed%10 2>&1 | tail -2
N=$(ls $ROOT/results/anchor/ 2>/dev/null | wc -l)
P=$(grep -l '"passed": true' $ROOT/results/anchor/*.json 2>/dev/null | wc -l)
echo "anchor_files=$N passed=$P"
if [ "$P" = "27" ]; then
  echo "=== GATE PASS -> SUBMIT FORMAL TRAIN ARRAY ==="
  out=$(sbatch --array=0-107 $ROOT/slurm/tukf23_train.slurm 2>&1); echo "$out"
  JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
  [ -n "$JID" ] || { echo "SUBMIT_FAILED"; exit 1; }
  echo "train_array_v2=$JID"
else
  echo "GATE_NOT_READY"
fi
