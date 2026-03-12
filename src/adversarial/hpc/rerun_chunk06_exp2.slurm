#!/usr/bin/env bash
#SBATCH -J fix06-e2
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 02:00:00
#SBATCH -o logs/05_adversarial/fix06_exp2.out
#SBATCH -e logs/05_adversarial/fix06_exp2.err

set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

CFG=src/adversarial/configs/full_eval.yaml
BF=src/adversarial/data/train_540_basins.txt

echo "=== Fix chunk_06 Exp2: 8 constraint x eps combos ==="
echo "Node: $(hostname), Start: $(date)"

for CONSTRAINT in lp physical statistical; do
    for EPS in 0.05 0.1 0.2; do
        if [ "$CONSTRAINT" = "lp" ] && [ "$EPS" = "0.05" ]; then
            continue
        fi
        echo "--- APGD ${CONSTRAINT} eps=${EPS} ---"
        python -u src/adversarial/scripts/run_adversarial_eval.py \
            --config $CFG --basin-file $BF --basin-range 300:350 \
            --attack auto_pgd --epsilon ${EPS} --constraint ${CONSTRAINT} \
            --target untargeted --n-samples 1 \
            --output-suffix "exp2_${CONSTRAINT}_eps${EPS}_chunk_06"
    done
done

echo "=== Done: $(date) ==="
