#!/usr/bin/env bash
# =============================================================================
# Mamba CAMELS-H Full Training (HPC)
# All basins, 30 Epochs, seq_length=336
# Purpose: Full-scale benchmark comparison with LSTM
# Usage: sbatch src/mamba_camelsh/hpc/submit_full.slurm
# =============================================================================
#SBATCH --job-name=nh_mamba_camelsh_full
#SBATCH --partition=hgpu8
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --time=168:00:00         # 7 days for full training
#SBATCH --exclude=ngu001,ngu201,ngu202
#SBATCH --output=logs/03_mamba_camelsh/%j.out
#SBATCH --error=logs/03_mamba_camelsh/%j.err

set -eo pipefail

# =============================================================================
# Configuration
# =============================================================================
CONDA_ENV="${CONDA_ENV:-nh_final}"
CONFIG_FILE="src/mamba_camelsh/configs/camelsh_full.yml"
TASK_NAME="Mamba CAMELS-H Full Training (all basins, 30 epochs)"

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

# Mamba backend check (consistent with mamba.py logic)
python -c "
backend = None
try:
    from mamba_ssm import Mamba
    backend = 'mamba_ssm'
    print('[INFO] Mamba backend: mamba_ssm (CUDA kernel) ✓')
except ImportError as e:
    print(f'[DEBUG] mamba_ssm unavailable: {e}')

if backend is None:
    try:
        from transformers import MambaConfig, MambaModel
        backend = 'transformers'
        print('[INFO] Mamba backend: transformers (HuggingFace) ✓')
    except ImportError as e:
        print(f'[ERROR] transformers.Mamba unavailable: {e}')
        print('[ERROR] Need transformers>=4.36 for MambaModel!')

if backend is None:
    print('[FATAL] No Mamba backend! Install: pip install transformers>=4.39')
    exit(1)
"

# =============================================================================
# Training
# =============================================================================
echo ""
echo "[$(date)] Starting training..."
srun python -u -m neuralhydrology.nh_run train --config-file "$CONFIG_FILE"

EXIT_CODE=$?
echo ""
echo "[$(date)] Training finished (exit: $EXIT_CODE)"
echo "=========================================="
exit $EXIT_CODE
