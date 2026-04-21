#!/usr/bin/env bash
#SBATCH -J adv-fix06
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 03:00:00
#SBATCH -o logs/05_adversarial/fix06.out
#SBATCH -e logs/05_adversarial/fix06.err

# Rerun ALL missing chunk_06 (basins 300-350) experiments in one job

set -eo pipefail

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

CFG=src/adversarial/configs/full_eval.yaml
BF=src/adversarial/data/train_540_basins.txt
RANGE="300:350"
CID="06"

echo "=== Rerun chunk_06 (basins 300:350) ==="
echo "Node: $(hostname), Job: $SLURM_JOB_ID, Start: $(date)"

# --- Exp 1: missing 4 attacks ---
for ATTACK in fgsm gaussian_noise multiplicative_bias temporal_correlated_noise; do
    echo "--- Exp1 ${ATTACK} ---"
    python -u src/adversarial/scripts/run_adversarial_eval.py \
        --config $CFG --basin-file $BF --basin-range ${RANGE} \
        --attack ${ATTACK} --constraint lp --target untargeted \
        --n-samples 1 --output-suffix "exp1_${ATTACK}_chunk_${CID}"
done

# --- Exp 2: missing 8 constraint x eps combos ---
for CONSTRAINT in lp physical statistical; do
    for EPS in 0.05 0.1 0.2; do
        # skip lp_eps0.05 (already exists)
        if [ "$CONSTRAINT" = "lp" ] && [ "$EPS" = "0.05" ]; then
            continue
        fi
        echo "--- Exp2 ${CONSTRAINT} eps=${EPS} ---"
        python -u src/adversarial/scripts/run_adversarial_eval.py \
            --config $CFG --basin-file $BF --basin-range ${RANGE} \
            --attack auto_pgd --epsilon ${EPS} --constraint ${CONSTRAINT} \
            --target untargeted --n-samples 1 \
            --output-suffix "exp2_${CONSTRAINT}_eps${EPS}_chunk_${CID}"
    done
done

# --- Exp 3: missing flood and lowflow ---
for TARGET in flood lowflow; do
    echo "--- Exp3 ${TARGET} ---"
    python -u src/adversarial/scripts/run_adversarial_eval.py \
        --config $CFG --basin-file $BF --basin-range ${RANGE} \
        --attack auto_pgd --epsilon 0.1 --constraint lp --target ${TARGET} \
        --n-samples 1 --output-suffix "exp3_${TARGET}_chunk_${CID}"
done

echo "=== Done: $(date) ==="
