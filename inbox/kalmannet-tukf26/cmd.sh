#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf26_20260831
echo "=== TRAIN ARRAY 217272 STATES ==="
sacct -j 217272 --format=State --noheader 2>/dev/null | awk '{print $1}' | sort | uniq -c || true
echo "=== FAILURES ==="
sacct -j 217272 -X -n -P --format=JobID,State,ExitCode,Elapsed 2>/dev/null | grep -E '(FAILED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo "  none"
N=$(ls $ROOT/results/train/*.json 2>/dev/null | wc -l)
echo "train_records=$N / 135"
if [ "$N" = "135" ]; then
  echo "=== SBATCH READOUT ARRAY ==="
  if squeue -u $USER -h -o "%j" 2>/dev/null | grep -q tukf26_readout; then echo QUEUED_ALREADY
  else
    out=$(sbatch $ROOT/slurm/tukf26_readout.slurm 2>&1); echo "$out"
    echo "$out" | grep -qE 'Submitted batch job [0-9]+' || { echo "SUBMIT_FAILED"; exit 1; }
  fi
else
  echo "NOT_COMPLETE_YET"
fi
exit 0
