#!/usr/bin/env bash
#SBATCH -J q_armC_us_minus_net
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002   # documented bad node: nvidia-smi sees 1 of 2 cards,
                           # torch reports CUDA unknown error. MUST be a directive:
                           # on the command line the xbatch wrapper silently drops it.
#SBATCH -t 24:00:00
#SBATCH -o logs/attr_swap/armC_usminus4-%j.out
#SBATCH -e logs/attr_swap/armC_usminus4-%j.err

# ARM C of the stream-network ablation: 12 US attributes MINUS the 4 network ones.
#
# Same 40-epoch cap and same frozen contract as hpc_train_q_control.sbatch and
# hpc_train_q_hydroatlas.sbatch -- if you change the cap in one, change it in all
# three or the comparison is void.
#
# Read the verdict from the PAIRED per-station comparison against the control arm,
# not from the median printed at the end of the training script.

set -eo pipefail

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate "${CONDA_ENV:-nh_final}"

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export CUDA_DEVICE_ORDER=PCI_BUS_ID

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH
mkdir -p logs/attr_swap

echo "[$(date)] Job $SLURM_JOB_ID on $(hostname)"
python -c "import torch; print(f'PyTorch {torch.__version__}, CUDA {torch.cuda.is_available()}')"

# Fail fast if this node has no usable GPU. Without this the training silently falls
# back to CPU (the trainer's --device default) and burns days producing nothing --
# exactly what happened on ngu002 in jobs 205848 / 205854 on 2026-08-19.
python - <<'PYCHK' || { echo "[FATAL] no usable GPU on $(hostname) -- refusing to train on CPU"; exit 1; }
import sys, torch
sys.exit(0 if torch.cuda.is_available() else 1)
PYCHK

srun python -u scripts/chain_train_q_us_minus_network.py \
  --output_dir models/q_lstm_usminus4_hpc_s42 --seed 42 --epochs 40 --num_workers 4

echo "[$(date)] training done"
srun python -u scripts/chain_eval_q_us_minus_network.py \
  --model_dir models/q_lstm_usminus4_hpc_s42 --subset val --max_hours 43800
echo "[$(date)] Done (exit: $?)"
