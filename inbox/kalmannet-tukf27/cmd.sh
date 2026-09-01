#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf27_20260901
echo "=== TRAIN 217690 ==="
sacct -j 217690 --format=State --noheader 2>/dev/null | awk '{print $1}' | sort | uniq -c || true
sacct -j 217690 -X -n -P --format=JobID,State,ExitCode 2>/dev/null | grep -E '(FAILED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo "  none"
N=$(ls $ROOT/results/train/*.json 2>/dev/null | wc -l)
echo "train_records=$N / 108"
if [ "$N" = "108" ]; then
  echo "=== SBATCH READOUT ==="
  if squeue -u $USER -h -o "%j" 2>/dev/null | grep -q tukf27_readout; then echo QUEUED_ALREADY
  else
    out=$(sbatch $ROOT/slurm/tukf27_readout.slurm 2>&1); echo "$out"
    echo "$out" | grep -qE 'Submitted batch job [0-9]+' || { echo "SUBMIT_FAILED"; exit 1; }
  fi
else
  echo "NOT_COMPLETE_YET"
fi
exit 0
