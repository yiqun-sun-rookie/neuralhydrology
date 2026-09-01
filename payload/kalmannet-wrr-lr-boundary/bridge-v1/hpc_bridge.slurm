#!/bin/bash
#SBATCH --job-name=knet-lr-common
#SBATCH --partition=hgpu2p
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --time=1-00:00:00
#SBATCH --exclude=ngu002
#SBATCH --output=/data1/home/sunyiq/kalmannet_wrr_lr_boundary_20260901/logs/slurm-%j.out
#SBATCH --error=/data1/home/sunyiq/kalmannet_wrr_lr_boundary_20260901/logs/slurm-%j.err

set -eo pipefail

ROOT=/data1/home/sunyiq/kalmannet_wrr_lr_boundary_20260901
REPO="$ROOT/repo"
EXPERIMENT="$REPO/experiments/optimize_hyper_parameters/validation_lr_boundary_20260831"

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export PYTHONNOUSERSITE=1
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-4}"

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate knet_clean

cd "$REPO"
echo "job_id=$SLURM_JOB_ID"
echo "host=$(hostname)"
echo "started=$(date -Is)"
echo "cuda_visible_devices=$CUDA_VISIBLE_DEVICES"
nvidia-smi -L
nvidia-smi --query-gpu=timestamp,name,uuid,driver_version,memory.total --format=csv,noheader

python -u - <<'PY'
import json
import os
import platform
from pathlib import Path

import numpy
import torch
import yaml

try:
    import optuna
    optuna_version = optuna.__version__
except Exception as exc:
    optuna_version = f"IMPORT_FAILED:{type(exc).__name__}:{exc}"

if not torch.cuda.is_available():
    raise RuntimeError("CUDA is unavailable inside the Slurm allocation")
gpu_name = torch.cuda.get_device_name(0)
if "RTX 3090" not in gpu_name:
    raise RuntimeError(f"Unexpected GPU model: {gpu_name}")

runtime = {
    "slurm_job_id": os.environ.get("SLURM_JOB_ID"),
    "slurm_job_node": os.environ.get("SLURMD_NODENAME"),
    "cuda_visible_devices": os.environ.get("CUDA_VISIBLE_DEVICES"),
    "python": platform.python_version(),
    "platform": platform.platform(),
    "torch": torch.__version__,
    "cuda_build": torch.version.cuda,
    "cudnn": torch.backends.cudnn.version(),
    "numpy": numpy.__version__,
    "pyyaml": yaml.__version__,
    "optuna": optuna_version,
    "gpu": gpu_name,
    "gpu_count_visible": torch.cuda.device_count(),
}
path = Path("experiments/optimize_hyper_parameters/validation_lr_boundary_20260831/hpc_runtime.json")
path.write_text(json.dumps(runtime, indent=2), encoding="utf-8")
print(json.dumps(runtime, indent=2))
PY

python -u "$EXPERIMENT/run_one_lr.py" --index 0 --smoke
python -u "$EXPERIMENT/run_one_lr.py" --index 0
python -u "$EXPERIMENT/summarize_bridge.py"

echo "finished=$(date -Is)"
