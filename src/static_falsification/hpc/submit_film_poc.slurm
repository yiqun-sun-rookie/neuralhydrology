#!/bin/bash
#SBATCH --job-name=film_poc
#SBATCH --partition=hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=12:00:00
#SBATCH --array=0-23%8
#SBATCH --output=logs/11_static_falsification/film_poc_%A_%a.out
#SBATCH --error=logs/11_static_falsification/film_poc_%A_%a.err

# --array=0-23%8 -> 24 jobs, max 8 concurrent
# Matrix: 2 models x 2 static conditions x 2 folds x 3 seeds = 24

set -euo pipefail

CONFIGS=(
    src/static_falsification/configs/film_poc/ealstm_poc_real_fold0_seed0.yml
    src/static_falsification/configs/film_poc/ealstm_poc_real_fold0_seed1.yml
    src/static_falsification/configs/film_poc/ealstm_poc_real_fold0_seed2.yml
    src/static_falsification/configs/film_poc/ealstm_poc_real_fold1_seed0.yml
    src/static_falsification/configs/film_poc/ealstm_poc_real_fold1_seed1.yml
    src/static_falsification/configs/film_poc/ealstm_poc_real_fold1_seed2.yml
    src/static_falsification/configs/film_poc/ealstm_poc_shuffle_fold0_seed0.yml
    src/static_falsification/configs/film_poc/ealstm_poc_shuffle_fold0_seed1.yml
    src/static_falsification/configs/film_poc/ealstm_poc_shuffle_fold0_seed2.yml
    src/static_falsification/configs/film_poc/ealstm_poc_shuffle_fold1_seed0.yml
    src/static_falsification/configs/film_poc/ealstm_poc_shuffle_fold1_seed1.yml
    src/static_falsification/configs/film_poc/ealstm_poc_shuffle_fold1_seed2.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_real_fold0_seed0.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_real_fold0_seed1.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_real_fold0_seed2.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_real_fold1_seed0.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_real_fold1_seed1.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_real_fold1_seed2.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_shuffle_fold0_seed0.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_shuffle_fold0_seed1.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_shuffle_fold0_seed2.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_shuffle_fold1_seed0.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_shuffle_fold1_seed1.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_shuffle_fold1_seed2.yml
)

CFG="${CONFIGS[$SLURM_ARRAY_TASK_ID]}"

echo "=== Task $SLURM_ARRAY_TASK_ID: $CFG ==="
echo "Start: $(date)"

cd $HOME/neuralhydrology

source activate nh

mkdir -p logs/11_static_falsification

python src/static_falsification/scripts/run_film_poc.py \
    --config-file "$CFG" \
    --gpu 0

echo "End: $(date)"
