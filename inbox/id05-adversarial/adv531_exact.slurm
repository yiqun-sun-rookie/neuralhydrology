#!/usr/bin/env bash
# Exact-moment counterfactual on all 531 basins (was a 13-basin subset in the current draft).
#SBATCH -J adv531_exact
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH --array=0-4
#SBATCH -t 12:00:00
#SBATCH -o /data1/home/sunyiq/adv531/logs/%x_%A_%a.out
#SBATCH -e /data1/home/sunyiq/adv531/logs/%x_%A_%a.err

set -eo pipefail

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd /data1/home/${USER}/adv531
export PYTHONPATH=$(pwd):$PYTHONPATH
mkdir -p logs

echo "[$(date)] exact-moment counterfactual, chunk ${SLURM_ARRAY_TASK_ID}/4, node $(hostname)"
python -u src/adversarial/scripts/run_exact_moment_probe.py \
    --eps 0.1 --from-records \
    --n-chunks 5 --offset ${SLURM_ARRAY_TASK_ID} \
    --device cuda:0
echo "[$(date)] chunk ${SLURM_ARRAY_TASK_ID} done"
