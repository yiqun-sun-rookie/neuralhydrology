#!/bin/bash
#SBATCH --job-name=adv-exp1
#SBATCH --partition=hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --array=0-10
#SBATCH --output=logs/05_adversarial/exp1_%a.out
#SBATCH --error=logs/05_adversarial/exp1_%a.err

# Exp 1: Core attack comparison
# 5 methods x 4 eps x ~50 basins/chunk x 1 sample ≈ 45 min/chunk
# Methods: auto_pgd, fgsm, gaussian_noise, multiplicative_bias, temporal_correlated_noise

CHUNK_SIZE=50
START=$((SLURM_ARRAY_TASK_ID * CHUNK_SIZE))
END=$((START + CHUNK_SIZE))
CHUNK_ID=$(printf '%02d' $SLURM_ARRAY_TASK_ID)

cd ~/neuralhydrology
source activate nh  # adjust to actual conda env name

echo "=== Exp 1 chunk ${CHUNK_ID}: basins ${START}:${END} ==="
echo "Start: $(date)"

for ATTACK in auto_pgd fgsm gaussian_noise multiplicative_bias temporal_correlated_noise; do
    echo "--- Running ${ATTACK} ---"
    python -u src/adversarial/scripts/run_adversarial_eval.py \
        --config src/adversarial/configs/full_eval.yaml \
        --basin-file src/adversarial/data/train_540_basins.txt \
        --basin-range ${START}:${END} \
        --attack ${ATTACK} \
        --constraint lp \
        --target untargeted \
        --n-samples 1 \
        --output-suffix "exp1_${ATTACK}_chunk_${CHUNK_ID}"
done

echo "End: $(date)"
