#!/usr/bin/env bash
#SBATCH -J adv-cw
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 04:00:00
#SBATCH --array=0-19
#SBATCH -o logs/05_adversarial/cw_%a.out
#SBATCH -e logs/05_adversarial/cw_%a.err
#SBATCH --exclude=ngu001,ngu201,ngu202

# Exp 5: C&W minimum perturbation (slow: ~15s/basin on GPU)
# 540 basins / 20 chunks = 27 basins/chunk

set -eo pipefail

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

CHUNK_SIZE=27
START=$((SLURM_ARRAY_TASK_ID * CHUNK_SIZE))
END=$((START + CHUNK_SIZE))
CHUNK_ID=$(printf '%02d' $SLURM_ARRAY_TASK_ID)

CFG=src/adversarial/configs/full_eval.yaml
BF=src/adversarial/data/train_540_basins.txt

echo "=== Exp 5 C&W chunk ${CHUNK_ID}: basins ${START}:${END} ==="
echo "Node: $(hostname), Job: $SLURM_JOB_ID, Start: $(date)"

python -u src/adversarial/scripts/run_adversarial_eval.py \
    --config $CFG \
    --basin-file $BF \
    --basin-range ${START}:${END} \
    --attack cw_regression \
    --epsilon 0.1 \
    --constraint lp \
    --target untargeted \
    --n-samples 1 \
    --output-suffix "exp5_cw_chunk_${CHUNK_ID}"

echo "End: $(date)"
