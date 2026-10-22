#!/bin/bash
# A1 training 246279 failed in ~15 s on ngu102 (hgpu4). Hold own A1+DA 246280 (its afterany dep is now satisfied, it
# would run on missing models), then read the failure logs. Nothing else touched.
set -o pipefail
NEW=/data1/home/sunyiq/ohn_da_vs_ar_531_20261021
date --iso-8601=seconds
scontrol hold 246280 2>&1 && echo "HELD 246280"
squeue -j 246280,246281 -h -o '%i|%T|%R' 2>&1 | head -4
echo "=== A1 LOGS ==="
ls -la $NEW/logs | grep -E '246279' | head -12
for T in 0 1; do
  for E in err out; do
    f=$(ls $NEW/logs/*246279_${T}.$E 2>/dev/null | head -1)
    echo "--- $f"; [ -n "$f" ] && tail -n 40 "$f"
  done
done
echo "=== A1 RUN DIRS ==="
ls -la $NEW/runs 2>&1 | head -20
echo "=== SLURM HEAD ==="
grep -nE '^#SBATCH|python|run_cli|train' $NEW/slurm/p2_a1_train.slurm | head -30
echo "SEQ28_DONE"
