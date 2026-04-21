#!/usr/bin/env bash
#SBATCH -J adv-exp2
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 02:00:00
#SBATCH --array=0-10
#SBATCH -o logs/05_adversarial/exp2_%a.out
#SBATCH -e logs/05_adversarial/exp2_%a.err

# Exp 2: Constraint ablation (APGD x 3 eps x 3 constraints)

set -eo pipefail

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

CHUNK_SIZE=50
START=$((SLURM_ARRAY_TASK_ID * CHUNK_SIZE))
END=$((START + CHUNK_SIZE))
CHUNK_ID=$(printf '%02d' $SLURM_ARRAY_TASK_ID)

CFG=src/adversarial/configs/full_eval.yaml
BF=src/adversarial/data/train_540_basins.txt

echo "=== Exp 2 chunk ${CHUNK_ID}: basins ${START}:${END} ==="
echo "Node: $(hostname), Job: $SLURM_JOB_ID, Start: $(date)"

for CONSTRAINT in lp physical statistical; do
    for EPS in 0.05 0.1 0.2; do
        echo "--- APGD constraint=${CONSTRAINT} eps=${EPS} ---"
        python -u src/adversarial/scripts/run_adversarial_eval.py \
            --config $CFG \
            --basin-file $BF \
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
