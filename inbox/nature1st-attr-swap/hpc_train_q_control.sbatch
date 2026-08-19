#!/usr/bin/env bash
#SBATCH -J q_ctrl_us_attrs
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002   # documented bad node: nvidia-smi sees 1 of 2 cards,
                           # torch reports CUDA unknown error. MUST be a directive:
                           # on the command line the xbatch wrapper silently drops it.
#SBATCH -t 24:00:00
#SBATCH -o logs/attr_swap/control-%j.out
#SBATCH -e logs/attr_swap/control-%j.err

# CONTROL arm on the cluster: the ORIGINAL 12 US-only attributes.
#
# Why this must be re-run here instead of reusing the local 0.6474: that number was
# produced on a different GPU with a different PyTorch build, and the effect under
# test is only 0.01-0.04 wide. Comparing across environments would confound the
# attribute question with a software-version question. Both arms run here, same node
# type, same env, same 40-epoch cap.
#
# 40 epochs (not the local 20) because the local treatment arm hit the 20-epoch cap
# while still improving; both arms now get room to early-stop on their own.

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

srun python -u scripts/chain_train_q_v1.py \
  --window 168 --horizon 1 --stride 24 \
  --daily_days 365 --max_hours 43800 \
  --epochs 40 --patience 5 --batch_size 256 --lr 5e-4 \
  --lstm_hidden 256 --lstm_layers 2 \
  --static_hidden 64 --mlp_hidden 128 --dropout 0.2 \
  --initial_forget_bias 5.0 \
  --seed 42 --num_workers 4 \
  --output_dir models/q_lstm_control_hpc_s42 --require_empty_output_dir

echo "[$(date)] training done"
srun python -u scripts/chain_eval_q.py \
  --model_dir models/q_lstm_control_hpc_s42 --subset val --max_hours 43800
echo "[$(date)] Done (exit: $?)"
