#!/bin/bash
#SBATCH --job-name=sf_train
#SBATCH --partition=hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=06:00:00
#SBATCH --array=0-14
#SBATCH --output=logs/11_static_falsification/slurm_%A_%a.out
#SBATCH --error=logs/11_static_falsification/slurm_%A_%a.err

# Map array index to condition + fold
# 0-4: E1 fold 0-4, 5-9: E3 fold 0-4, 10-14: E4 fold 0-4
CONDITIONS=(e1 e1 e1 e1 e1 e3 e3 e3 e3 e3 e4 e4 e4 e4 e4)
FOLDS=(0 1 2 3 4 0 1 2 3 4 0 1 2 3 4)

CONDITION=${CONDITIONS[$SLURM_ARRAY_TASK_ID]}
FOLD=${FOLDS[$SLURM_ARRAY_TASK_ID]}

echo "=== Task $SLURM_ARRAY_TASK_ID: ${CONDITION} fold ${FOLD} ==="
echo "Start: $(date)"

cd $HOME/neuralhydrology

# Activate conda environment
source activate nh

python -m static_falsification.scripts.run_training \
    --condition ${CONDITION} \
    --fold ${FOLD} \
    --gpu 0

echo "End: $(date)"
