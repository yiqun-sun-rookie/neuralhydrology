#!/usr/bin/env bash
#SBATCH -J fix06-e3
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 01:00:00
#SBATCH -o logs/05_adversarial/fix06_exp3.out
#SBATCH -e logs/05_adversarial/fix06_exp3.err

set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

CFG=src/adversarial/configs/full_eval.yaml
BF=src/adversarial/data/train_540_basins.txt

echo "=== Fix chunk_06 Exp3: flood + lowflow ==="
echo "Node: $(hostname), Start: $(date)"

for TARGET in flood lowflow; do
    echo "--- APGD target=${TARGET} ---"
    python -u src/adversarial/scripts/run_adversarial_eval.py \
        --config $CFG --basin-file $BF --basin-range 300:350 \
        --attack auto_pgd --epsilon 0.1 --constraint lp --target ${TARGET} \
        --n-samples 1 --output-suffix "exp3_${TARGET}_chunk_06"
done

echo "=== Done: $(date) ==="
