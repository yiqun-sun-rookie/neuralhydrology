#!/usr/bin/env bash
# =============================================================================
# Mamba CAMELS-H Long Sequence Test (HPC)
# 50 Basins, 10 Epochs, seq_length=3000 (125 days)
# Purpose: Demonstrate Mamba's advantage in ultra-long sequences
# Usage: sbatch src/mamba_camelsh/hpc/submit_longseq.slurm
# =============================================================================
#SBATCH --job-name=nh_mamba_camelsh_longseq
#SBATCH --partition=hgpu8
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --time=120:00:00         # 5 days for long sequence test
#SBATCH --exclude=ngu001,ngu201,ngu202
#SBATCH --output=logs/03_mamba_camelsh/%j.out
#SBATCH --error=logs/03_mamba_camelsh/%j.err

set -eo pipefail

# =============================================================================
# Configuration
# =============================================================================
CONDA_ENV="${CONDA_ENV:-nh_final}"
CONFIG_FILE="src/mamba_camelsh/configs/camelsh_longseq.yml"
TASK_NAME="Mamba CAMELS-H Long Sequence Test (50 basins, seq=3000)"

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
echo "[INFO] Sequence length: 3000 hours (125 days)"

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
    print('[INFO] Long sequences will benefit significantly from CUDA acceleration')
except ImportError as e:
    print(f'[DEBUG] mamba_ssm unavailable: {e}')

if backend is None:
    try:
        from transformers import MambaConfig, MambaModel
        backend = 'transformers'
        print('[INFO] Mamba backend: transformers (HuggingFace) ✓')
        print('[WARNING] HuggingFace backend is slower for long sequences')
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
echo "[$(date)] Starting training with ultra-long sequences (3000 hours)..."
echo "[INFO] This test demonstrates Mamba's O(N) complexity advantage"
srun python -u -m neuralhydrology.nh_run train --config-file "$CONFIG_FILE"

EXIT_CODE=$?
echo ""
echo "[$(date)] Training finished (exit: $EXIT_CODE)"
echo "=========================================="
exit $EXIT_CODE
