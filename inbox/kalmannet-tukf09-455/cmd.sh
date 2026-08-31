#!/bin/bash
# Read-only cluster collision, capacity, data, and environment snapshot.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_20260831
DATA=/data1/home/sunyiq/neuralhydrology/data/camels_us

echo "=== RUNNER ==="
pgrep -af hpc_runner_active || true

echo "=== UNIQUE ROOT ==="
if [ -e "$ROOT" ]; then
  echo "ROOT_EXISTS=$ROOT"
else
  echo "ROOT_ABSENT=$ROOT"
fi

echo "=== SHARED DATA READINESS ==="
for path in \
  "$DATA" \
  "$DATA/basin_mean_forcing/maurer" \
  "$DATA/usgs_streamflow" \
  "$DATA/camels_attributes_v2.0/camels_topo.txt" \
  "$DATA/basin_mean_forcing/maurer/01/01022500_lump_maurer_forcing_leap.txt" \
  "$DATA/usgs_streamflow/01/01022500_streamflow_qc.txt"
do
  if [ -e "$path" ]; then
    stat -c 'PRESENT %F %s %n' "$path" || true
  else
    echo "MISSING $path"
  fi
done

echo "=== PARTITIONS ==="
sinfo -o '%.10P %.6a %.6D %.6t %.30N' || true
sinfo -R || true

echo "=== OWN JOBS ==="
squeue -u "$USER" -o '%.18i %.24j %.10P %.8T %.10M %.24R' || true

echo "=== STORAGE ==="
df -h /data1 || true

echo "=== CONDA ENVIRONMENTS ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source "$HOME/miniconda3/etc/profile.d/conda.sh" 2>/dev/null || true
conda env list 2>&1 || true

echo "=== CANDIDATE TORCH 2.2.2 INSTALLATIONS ==="
for prefix in /data1/home/${USER}/miniconda3/envs "$HOME/miniconda3/envs"; do
  [ -d "$prefix" ] || continue
  find "$prefix" -path '*/site-packages/torch/version.py' -type f -exec grep -l "__version__ = '2.2.2" {} \; 2>/dev/null || true
done

echo "=== CANDIDATE TORCH 2.2.2 WHEEL ==="
find "$HOME/.cache/pip" -type f -iname 'torch*2.2.2*.whl' -print -quit 2>/dev/null || true

echo "=== SNAPSHOT COMPLETE ==="
