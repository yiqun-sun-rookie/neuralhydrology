#!/usr/bin/env bash
# Moment/structure audit analysis over all 531 recorded whole-period-statistics perturbations.
# Pure numpy/pandas: no GPU needed, so it runs on the CPU partition to avoid the GPU queue.
#SBATCH -J adv531_analyze
#SBATCH -p hcpu48
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH -t 02:00:00
#SBATCH -o /data1/home/sunyiq/adv531/logs/%x_%j.out
#SBATCH -e /data1/home/sunyiq/adv531/logs/%x_%j.err

set -eo pipefail

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd /data1/home/${USER}/adv531
export PYTHONPATH=$(pwd):$PYTHONPATH
mkdir -p logs

echo "[$(date)] structure analysis on node $(hostname)"
python -u src/adversarial/scripts/analyze_statistical_structure.py --eps 0.1 --level statistical
echo "[$(date)] analysis done"
