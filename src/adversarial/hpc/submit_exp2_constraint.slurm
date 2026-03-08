#!/bin/bash
#SBATCH --job-name=adv-exp2
#SBATCH --partition=hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --array=0-10
#SBATCH --output=logs/05_adversarial/exp2_%a.out
#SBATCH --error=logs/05_adversarial/exp2_%a.err

# Exp 2: Constraint ablation (APGD x 3 eps x 3 constraints)

CHUNK_SIZE=50
START=$((SLURM_ARRAY_TASK_ID * CHUNK_SIZE))
END=$((START + CHUNK_SIZE))
CHUNK_ID=$(printf '%02d' $SLURM_ARRAY_TASK_ID)

cd ~/neuralhydrology
source activate nh

echo "=== Exp 2 chunk ${CHUNK_ID}: basins ${START}:${END} ==="

for CONSTRAINT in lp physical statistical; do
    for EPS in 0.05 0.1 0.2; do
        echo "--- APGD constraint=${CONSTRAINT} eps=${EPS} ---"
        python -u src/adversarial/scripts/run_adversarial_eval.py \
            --config src/adversarial/configs/full_eval.yaml \
            --basin-file src/adversarial/data/train_540_basins.txt \
            --basin-range ${START}:${END} \
            --attack auto_pgd \
            --epsilon ${EPS} \
            --constraint ${CONSTRAINT} \
            --target untargeted \
            --n-samples 1 \
            --output-suffix "exp2_${CONSTRAINT}_eps${EPS}_chunk_${CHUNK_ID}"
    done
done

echo "End: $(date)"
