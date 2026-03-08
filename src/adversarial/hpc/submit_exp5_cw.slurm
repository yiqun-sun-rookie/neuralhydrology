#!/bin/bash
#SBATCH --job-name=adv-cw
#SBATCH --partition=hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --array=0-19
#SBATCH --output=logs/05_adversarial/cw_%a.out
#SBATCH --error=logs/05_adversarial/cw_%a.err

# Exp 5: C&W minimum perturbation (slow: ~74s/basin on CPU, ~15s on GPU)
# 540 basins / 20 chunks = 27 basins/chunk ≈ 33 min/chunk (CPU) or 7 min (GPU)

CHUNK_SIZE=27
START=$((SLURM_ARRAY_TASK_ID * CHUNK_SIZE))
END=$((START + CHUNK_SIZE))
CHUNK_ID=$(printf '%02d' $SLURM_ARRAY_TASK_ID)

cd ~/neuralhydrology
source activate nh

echo "=== Exp 5 C&W chunk ${CHUNK_ID}: basins ${START}:${END} ==="

python -u src/adversarial/scripts/run_adversarial_eval.py \
    --config src/adversarial/configs/full_eval.yaml \
    --basin-file src/adversarial/data/train_540_basins.txt \
    --basin-range ${START}:${END} \
    --attack cw_regression \
    --epsilon 0.1 \
    --constraint lp \
    --target untargeted \
    --n-samples 1 \
    --output-suffix "exp5_cw_chunk_${CHUNK_ID}"

echo "End: $(date)"
