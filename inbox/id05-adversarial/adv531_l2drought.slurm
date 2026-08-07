#!/usr/bin/env bash
# Re-run the l2-signature and drought-mechanism analyses on all 531 basins.
# Reads 531 npz hydrograph records; pure numpy/pandas, so CPU partition.
#SBATCH -J adv531_l2drought
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

echo "########## L2 SIGNATURES ##########"
python -u src/adversarial/scripts/analyze_l2_signatures.py
echo "########## DROUGHT MECHANISM ##########"
python -u src/adversarial/scripts/analyze_drought_mechanism.py
echo "[$(date)] both done"
