#!/usr/bin/env bash
#SBATCH -J adv-smoke
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 00:10:00
#SBATCH -o logs/05_adversarial/smoke-%j.out
#SBATCH -e logs/05_adversarial/smoke-%j.err
#SBATCH --exclude=ngu001,ngu201,ngu202

set -eo pipefail

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

CFG=src/adversarial/configs/full_eval.yaml
BF=src/adversarial/data/train_540_basins.txt

echo "=== Smoke test start: $(date) ==="
echo "Node: $(hostname), Job: $SLURM_JOB_ID"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
python -c "import torch; print(f'PyTorch {torch.__version__}, CUDA: {torch.cuda.is_available()}')"

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
