#!/usr/bin/env bash
# =============================================================================
# LSTM CAMELS-H Mini Benchmark (HPC)
# 50 Basins, 10 Epochs, seq_length=168
# Purpose: Baseline comparison for Mamba experiments
# Usage: sbatch src/mamba_camelsh/hpc/submit_lstm_mini.slurm
# =============================================================================
#SBATCH --job-name=nh_lstm_camelsh_mini
#SBATCH --partition=hgpu8
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --time=24:00:00          # 1 day for LSTM mini benchmark (faster than Mamba)
#SBATCH --exclude=ngu001,ngu201,ngu202
#SBATCH --output=logs/03_mamba_camelsh/%j.out
#SBATCH --error=logs/03_mamba_camelsh/%j.err

set -eo pipefail

# =============================================================================
# Configuration
# =============================================================================
CONDA_ENV="${CONDA_ENV:-nh_final}"
CONFIG_FILE="src/mamba_camelsh/configs/camelsh_lstm_mini.yml"
TASK_NAME="LSTM CAMELS-H Mini Benchmark (50 basins, 10 epochs)"

# =============================================================================
# Environment Initialization
# =============================================================================
echo "=========================================="
echo "[$(date)] $TASK_NAME"
echo "=========================================="
echo "[INFO] Job ID: $SLURM_JOB_ID"
echo "[INFO] Node:   $(hostname)"
echo "[INFO] GPU:    ${CUDA_VISIBLE_DEVICES:-N/A}"
echo "[INFO] Config: $CONFIG_FILE"

# Conda activation (consistent with resume script)
source ~/.bashrc
module load miniconda3
conda activate "$CONDA_ENV" || { echo "[FATAL] Failed to activate $CONDA_ENV"; exit 1; }

# Fix PyTorch/MKL compatibility issues (iJIT_NotifyEvent)
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

# Working directory
cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH
mkdir -p logs/03_mamba_camelsh results/03_mamba_camelsh

# Verify LSTM model availability
python -c "
try:
    from neuralhydrology.modelzoo.cudalstm import CudaLSTM
    print('[INFO] CudaLSTM model available ✓')
except ImportError as e:
    print(f'[ERROR] CudaLSTM not available: {e}')
    exit(1)
"

# =============================================================================
# Training
# =============================================================================
echo ""
echo "[$(date)] Starting LSTM baseline training..."
srun python -u -m neuralhydrology.nh_run train --config-file "$CONFIG_FILE"

EXIT_CODE=$?
echo ""
echo "[$(date)] Training finished (exit: $EXIT_CODE)"
echo "=========================================="
exit $EXIT_CODE
