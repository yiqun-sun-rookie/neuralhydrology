#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf24_20260827
echo "=== SBATCH TRAIN TIMING SMOKE (basin 01047000 x 4 modes) ==="
cd $ROOT && sbatch --array=0,27,54,81 $ROOT/slurm/tukf24_train.slurm
squeue -u $USER -p hcpu48y 2>/dev/null | head -8 || true
