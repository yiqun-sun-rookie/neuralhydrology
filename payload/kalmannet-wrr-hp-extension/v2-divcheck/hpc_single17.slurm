#!/usr/bin/env bash
#SBATCH -J wrrhp-div
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 1-00:00:00
#SBATCH --array=17-17
#SBATCH -o /data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902/logs/slurm-%A_%a.out
#SBATCH -e /data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902/logs/slurm-%A_%a.err
# never write --mem on this cluster

set -eo pipefail

ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
REPO="$ROOT/repo"
EXPERIMENT="$REPO/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
IDX="${SLURM_ARRAY_TASK_ID:?SLURM_ARRAY_TASK_ID is not set}"

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export PYTHONNOUSERSITE=1
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-4}"

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate knet_clean || { echo "CONDA_FAILED"; exit 1; }

cd "$REPO"
echo "job_id=$SLURM_JOB_ID array_task=$IDX host=$(hostname) started=$(date -Is) cuda_visible_devices=$CUDA_VISIBLE_DEVICES"
nvidia-smi --query-gpu=name,uuid,driver_version,memory.total --format=csv,noheader --id=0 || true

# hard GPU check: never let a cell fall back to CPU
python - <<'PYCHK' || { echo "[FATAL] no usable GPU on $(hostname)"; exit 1; }
import sys, torch
ok = torch.cuda.is_available() and ("RTX 3090" in torch.cuda.get_device_name(0))
print("cuda", torch.cuda.is_available(), torch.cuda.get_device_name(0) if torch.cuda.is_available() else "-")
sys.exit(0 if ok else 1)
PYCHK

python -u "$EXPERIMENT/run_one_cell.py" --index "$IDX"
echo "finished=$(date -Is)"
