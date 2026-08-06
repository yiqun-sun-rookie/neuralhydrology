#!/usr/bin/env bash
#SBATCH -J adv531_exp2
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH --array=0-4
#SBATCH -t 24:00:00
#SBATCH -o /data1/home/sunyiq/adv531/logs/exp2_531_%A_%a.out
#SBATCH -e /data1/home/sunyiq/adv531/logs/exp2_531_%A_%a.err
# never write --mem

set -eo pipefail

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd /data1/home/${USER}/adv531
export PYTHONPATH=$(pwd):$PYTHONPATH
mkdir -p logs results/05_adversarial_robustness/id18_s100_hpc

OFFSET=${SLURM_ARRAY_TASK_ID}
OUT=results/05_adversarial_robustness/id18_s100_hpc/exp2_531_chunk${OFFSET}.json

echo "=========================================="
echo "[$(date)] exp2 constraint ablation, full 531, chunk ${OFFSET}/4"
echo "job=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}  node=$(hostname)"
python -c "import torch; print('torch', torch.__version__, '| cuda', torch.cuda.is_available(), '|', torch.cuda.get_device_name(0))"

# pre-flight: data + model must be in place, otherwise fail fast instead of
# discovering it ten hours later
[ -d data/camels_us/basin_mean_forcing/maurer ] || { echo "[FATAL] forcing dir missing"; exit 1; }
[ -f results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30/model_epoch030.pt ] || { echo "[FATAL] checkpoint missing"; exit 1; }
[ -f results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30/train_data/train_data_scaler.yml ] || { echo "[FATAL] scaler missing"; exit 1; }
echo "pre-flight OK -> ${OUT}"

python -u src/adversarial/scripts/run_exp2.py \
    --stride 5 --offset ${OFFSET} \
    --epsilons 0.05,0.1,0.2 \
    --levels lp,physical,statistical \
    --device cuda:0 \
    --out ${OUT}
EXIT_CODE=$?

echo "[$(date)] chunk ${OFFSET} done (exit ${EXIT_CODE})"
scontrol show job $SLURM_JOB_ID | head -12
exit ${EXIT_CODE}
