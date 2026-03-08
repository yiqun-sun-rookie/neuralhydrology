#!/bin/bash
#SBATCH --job-name=adv-exp3
#SBATCH --partition=hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --exclude=ngu001,ngu201,ngu202
#SBATCH --time=01:00:00
#SBATCH --array=0-10
#SBATCH --output=logs/05_adversarial/exp3_%a.out
#SBATCH --error=logs/05_adversarial/exp3_%a.err

# Exp 3: Targeted attacks (APGD x eps=0.1 x 3 targets)

CHUNK_SIZE=50
START=$((SLURM_ARRAY_TASK_ID * CHUNK_SIZE))
END=$((START + CHUNK_SIZE))
CHUNK_ID=$(printf '%02d' $SLURM_ARRAY_TASK_ID)

cd ~/neuralhydrology
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final

echo "=== Exp 3 chunk ${CHUNK_ID}: basins ${START}:${END} ==="

for TARGET in untargeted flood lowflow; do
    echo "--- APGD target=${TARGET} ---"
    python -u src/adversarial/scripts/run_adversarial_eval.py \
        --config src/adversarial/configs/full_eval.yaml \
        --basin-file src/adversarial/data/train_540_basins.txt \
        --basin-range ${START}:${END} \
        --attack auto_pgd \
        --epsilon 0.1 \
        --constraint lp \
        --target ${TARGET} \
        --n-samples 1 \
        --output-suffix "exp3_${TARGET}_chunk_${CHUNK_ID}"
done

echo "End: $(date)"
