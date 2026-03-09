#!/bin/bash
#SBATCH --job-name=adv-smoke
#SBATCH --partition=hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --exclude=ngu001,ngu201,ngu202
#SBATCH --time=00:10:00
#SBATCH --output=logs/05_adversarial/smoke.out
#SBATCH --error=logs/05_adversarial/smoke.err

cd ~/neuralhydrology
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final

CFG=src/adversarial/configs/full_eval.yaml
BF=src/adversarial/data/train_540_basins.txt

echo "=== Smoke test start: $(date) ==="
nvidia-smi

python -u src/adversarial/scripts/run_adversarial_eval.py \
    --config $CFG \
    --basin-file $BF \
    --basin-range 0:2 \
    --attack fgsm \
    --epsilon 0.1 \
    --n-samples 1 \
    --output-suffix hpc_smoke

echo "=== Smoke test end: $(date) ==="
echo "Results:"
ls -lh results/adversarial_eval/full/*hpc_smoke*
