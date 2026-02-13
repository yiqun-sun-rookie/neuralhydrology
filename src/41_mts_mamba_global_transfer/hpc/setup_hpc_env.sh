#!/bin/bash
set -euo pipefail

# Task 41 isolated HPC environment setup
CONDA_ENV="${CONDA_ENV:-neuralhydrology}"

module load anaconda3 2>/dev/null || true
if ! command -v conda >/dev/null 2>&1; then
  for croot in "$HOME/miniconda3" "$HOME/anaconda3" "/data0/software/anaconda3"; do
    if [ -f "$croot/etc/profile.d/conda.sh" ]; then
      source "$croot/etc/profile.d/conda.sh"
      break
    fi
  done
fi

if ! command -v conda >/dev/null 2>&1; then
  echo "[FATAL] conda not found." >&2
  exit 1
fi

eval "$(conda shell.bash hook)"
if ! conda env list | awk '{print $1}' | grep -qx "$CONDA_ENV"; then
  conda create -n "$CONDA_ENV" python=3.10 -y
fi
conda activate "$CONDA_ENV"

pip install -U pip
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu118
pip install xarray netcdf4 pandas numpy scipy matplotlib tqdm tensorboard ruamel.yaml

echo "[OK] Task 41 HPC env ready: $CONDA_ENV"
