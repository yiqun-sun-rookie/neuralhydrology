#!/usr/bin/env bash
#SBATCH -J adv-exp3
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 01:00:00
#SBATCH --array=0-10
#SBATCH -o logs/05_adversarial/exp3_%a.out
#SBATCH -e logs/05_adversarial/exp3_%a.err
#SBATCH --exclude=ngu001,ngu201,ngu202

# Exp 3: Targeted attacks (APGD x eps=0.1 x 3 targets)

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

echo "=== Exp 3 chunk ${CHUNK_ID}: basins ${START}:${END} ==="
echo "Node: $(hostname), Job: $SLURM_JOB_ID, Start: $(date)"

for TARGET in untargeted flood lowflow; do
    echo "--- APGD target=${TARGET} ---"
    python -u src/adversarial/scripts/run_adversarial_eval.py \
        --config $CFG \
        --basin-file $BF \
        --basin-range ${START}:${END} \
        --attack auto_pgd \
        --epsilon 0.1 \
        --constraint lp \
        --target ${TARGET} \
        --n-samples 1 \
        --output-suffix "exp3_${TARGET}_chunk_${CHUNK_ID}"
done

echo "End: $(date)"
