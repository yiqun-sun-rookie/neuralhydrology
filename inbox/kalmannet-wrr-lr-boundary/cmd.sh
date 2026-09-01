#!/bin/bash
set -o pipefail

echo "=== TIME_AND_HOST ==="
date -Is
hostname

echo "=== RUNNER ==="
pgrep -af hpc_runner_active || true

echo "=== GPU_PARTITIONS ==="
sinfo -h -o '%P|%a|%l|%D|%t|%N|%G' | grep -E '^hgpu(2p|2|4|8)' || true
sinfo -R || true

echo "=== OWN_JOBS ==="
squeue -u "$USER" -o '%i|%j|%T|%P|%M|%R' || true

echo "=== KALMANNET_ROOTS ==="
for root in /data1/home/sunyiq/kalmannet /data1/home/sunyiq/knet_project; do
  if [ -d "$root" ]; then
    echo "ROOT_OK=$root"
    (cd "$root" && printf 'branch=' && git rev-parse --abbrev-ref HEAD 2>/dev/null || true; printf 'head=' && git rev-parse --short HEAD 2>/dev/null || true)
  else
    echo "ROOT_MISSING=$root"
  fi
done

echo "=== TRAIN_VALIDATION_FILES ==="
for root in /data1/home/sunyiq/kalmannet /data1/home/sunyiq/knet_project; do
  for rel in data/processed/high_flow_aug/train_win800_19990101_01-20070527_03.pt data/processed/high_flow_aug/val_win800_20070527_04-20090314_13.pt; do
    f="$root/$rel"
    if [ -f "$f" ]; then
      stat -c 'FILE_OK=%n|bytes=%s|mtime=%y' "$f"
    else
      echo "FILE_MISSING=$f"
    fi
  done
done

echo "=== CONDA_ENVS ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source "$HOME/miniconda3/etc/profile.d/conda.sh" 2>/dev/null || true
conda env list 2>&1 || true
