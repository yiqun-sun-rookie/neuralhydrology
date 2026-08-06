#!/usr/bin/env bash
# Full-531 re-run of one experiment block, split into 5 disjoint basin chunks.
#   sbatch adv531_block.slurm <block>
# offset 0 reproduces the published 107-basin subset exactly, which doubles as a
# consistency check against the numbers already in the manuscript.
#SBATCH -J adv531
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH --array=0-4
#SBATCH -t 48:00:00
#SBATCH -o /data1/home/sunyiq/adv531/logs/%x_%A_%a.out
#SBATCH -e /data1/home/sunyiq/adv531/logs/%x_%A_%a.err
# never write --mem

set -eo pipefail

BLOCK=${1:?usage: sbatch adv531_block.slurm <exp2|exp3|exp4|exp5|exp6|detect|l1l2|ksweep>}

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd /data1/home/${USER}/adv531
export PYTHONPATH=$(pwd):$PYTHONPATH
O=${SLURM_ARRAY_TASK_ID}
R=results/05_adversarial_robustness/id18_s100_hpc
mkdir -p logs $R

echo "=========================================="
echo "[$(date)] block=${BLOCK} chunk=${O}/4  job=${SLURM_ARRAY_JOB_ID}_${O}  node=$(hostname)"
python -c "import torch; print('torch', torch.__version__, '| cuda', torch.cuda.is_available(), '|', torch.cuda.get_device_name(0))"

# fail fast rather than discovering a missing input ten hours in
[ -d data/camels_us/basin_mean_forcing/maurer ] || { echo "[FATAL] forcing dir missing"; exit 1; }
M=results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30
[ -f $M/model_epoch030.pt ] || { echo "[FATAL] checkpoint missing"; exit 1; }
[ -f $M/train_data/train_data_scaler.yml ] || { echo "[FATAL] scaler missing"; exit 1; }

S=src/adversarial/scripts
case "$BLOCK" in
  exp2)   CMD="$S/run_exp2.py --stride 5 --offset $O --epsilons 0.05,0.1,0.2 --levels lp,physical,statistical --out $R/exp2_531_chunk${O}.json" ;;
  exp3)   CMD="$S/run_exp3.py --stride 5 --offset $O --eps 0.1 --out $R/exp3_531_chunk${O}.json" ;;
  exp4)   CMD="$S/run_exp4.py --stride 5 --offset $O --eps 0.1 --random-control --out $R/exp4_531_chunk${O}.json" ;;
  exp5)   CMD="$S/run_exp5.py --stride 5 --offset $O --out $R/exp5_531_chunk${O}.json" ;;
  exp6)   CMD="$S/run_exp6.py --stride 5 --offset $O --eps 0.1 --out $R/exp6_531_chunk${O}.json" ;;
  detect) CMD="$S/run_exp_detect.py --stride 5 --offset $O --eps 0.1 --out $R/detect_531_chunk${O}.json" ;;
  l1l2)   CMD="$S/run_exp_l1l2.py --stride 5 --offset $O --eps 0.1 --out-dir $R/l1l2_531" ;;
  ksweep) CMD="$S/run_ksweep.py --stride 5 --offset $O --k-max 2000 --out $R/ksweep_531_chunk${O}.json" ;;
  *) echo "[FATAL] unknown block: $BLOCK"; exit 1 ;;
esac

echo "cmd: python -u $CMD"
python -u $CMD
EXIT_CODE=$?
echo "[$(date)] block=${BLOCK} chunk=${O} done (exit ${EXIT_CODE})"
exit ${EXIT_CODE}
