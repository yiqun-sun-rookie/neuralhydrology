#!/bin/bash
#SBATCH -J t41-caravan-global
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=16
#SBATCH --gres=gpu:1
#SBATCH --mem=128G
#SBATCH -t 72:00:00
#SBATCH --signal=TERM@300
#SBATCH -o logs/mts_mamba_global_transfer/caravan-%j.out
#SBATCH -e logs/mts_mamba_global_transfer/caravan-%j.err
#SBATCH --exclude=ngu201

set -euo pipefail

WORKDIR="/data1/home/${USER}/neuralhydrology"
TASK_ROOT="src/mts_mamba_global_transfer"
CONFIG_FILE="${TASK_ROOT}/configs/caravan_daily_basemodel_hpc.yml"
CONDA_ENV="${CONDA_ENV:-neuralhydrology}"

mkdir -p "${WORKDIR}/logs/mts_mamba_global_transfer"
mkdir -p "${WORKDIR}/results/mts_mamba_global_transfer"
cd "${WORKDIR}"

module load anaconda3 2>/dev/null || true
eval "$(conda shell.bash hook)"
conda activate "${CONDA_ENV}"

export MKL_THREADING_LAYER=GNU
export CUDA_DEVICE_ORDER=PCI_BUS_ID

echo "[INFO] job_id=${SLURM_JOB_ID}"
echo "[INFO] host=$(hostname)"
echo "[INFO] config=${CONFIG_FILE}"

srun --ntasks=1 --cpus-per-task="${SLURM_CPUS_PER_TASK}" --gpus=1 \
  python -u -m neuralhydrology.nh_run train --config-file "${CONFIG_FILE}"
