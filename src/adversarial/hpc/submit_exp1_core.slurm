#!/usr/bin/env bash
#SBATCH -J adv-exp1
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 02:00:00
#SBATCH --array=0-10
#SBATCH -o logs/05_adversarial/exp1_%a.out
#SBATCH -e logs/05_adversarial/exp1_%a.err

# Exp 1: Core attack comparison
# 5 methods x 4 eps x ~50 basins/chunk x 1 sample

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

echo "=== Exp 1 chunk ${CHUNK_ID}: basins ${START}:${END} ==="
echo "Node: $(hostname), Job: $SLURM_JOB_ID, Start: $(date)"

for ATTACK in auto_pgd fgsm gaussian_noise multiplicative_bias temporal_correlated_noise; do
    echo "--- Running ${ATTACK} ---"
    python -u src/adversarial/scripts/run_adversarial_eval.py \
        --config $CFG \
        --basin-file $BF \
        --basin-range ${START}:${END} \
        --attack ${ATTACK} \
        --constraint lp \
        --target untargeted \
        --n-samples 1 \
        --output-suffix "exp1_${ATTACK}_chunk_${CHUNK_ID}"
done

echo "End: $(date)"
