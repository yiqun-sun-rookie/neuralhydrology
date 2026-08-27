#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf24_20260827
echo "=== SBATCH FORMAL TRAIN ARRAY (0-107, smoke cells resume-skip) ==="
cd $ROOT && sbatch --array=0-107 $ROOT/slurm/tukf24_train.slurm
echo "=== QUEUE SNAPSHOT ==="
squeue -u $USER -p hcpu48y 2>/dev/null | head -12 || true
