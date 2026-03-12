#!/usr/bin/env bash
#SBATCH -J fix06-e1
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 01:00:00
#SBATCH -o logs/05_adversarial/fix06_exp1.out
#SBATCH -e logs/05_adversarial/fix06_exp1.err

set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

CFG=src/adversarial/configs/full_eval.yaml
BF=src/adversarial/data/train_540_basins.txt

echo "=== Fix chunk_06 Exp1: 3 random baselines ==="
echo "Node: $(hostname), Start: $(date)"

for ATTACK in gaussian_noise multiplicative_bias temporal_correlated_noise; do
    echo "--- ${ATTACK} ---"
    python -u src/adversarial/scripts/run_adversarial_eval.py \
        --config $CFG --basin-file $BF --basin-range 300:350 \
        --attack ${ATTACK} --constraint lp --target untargeted \
        --n-samples 1 --output-suffix "exp1_${ATTACK}_chunk_06"
done

echo "=== Done: $(date) ==="
