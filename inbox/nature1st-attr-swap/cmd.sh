#!/bin/bash
# nature1st-attr-swap seq=1 -- READ-ONLY probe. No sbatch, no compute, no writes
# outside this channel. Verifies the payload transferred earlier today is intact and
# that the partition is usable, before asking the user to authorise two GPU jobs.
set -o pipefail

echo "=== WHO ==="
hostname; whoami; date

echo "=== PAYLOAD ==="
ls -la /data1/home/sunyiq/nature_1st 2>&1 | head -15

echo "=== PREFLIGHT ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>&1 | head -3
cd /data1/home/sunyiq/nature_1st 2>&1 && python scripts/hpc_preflight.py 2>&1 | tail -22

echo "=== SBATCH SCRIPTS PRESENT ==="
ls -la /data1/home/sunyiq/nature_1st/scripts/hpc_train_q_*.sbatch 2>&1

echo "=== QUEUE (mine) ==="
squeue -u sunyiq -o "%.10i %.14j %.9P %.8T %.10M %.9l" 2>&1 | head -12

echo "=== PARTITION hgpu2p ==="
sinfo -p hgpu2p -o "%.12P %.6a %.6D %.12T %.20N" 2>&1 | head -8

echo "=== DISK ==="
df -h /data1 2>&1 | tail -2
echo "=== END seq=1 ==="
