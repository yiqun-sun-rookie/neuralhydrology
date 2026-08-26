#!/usr/bin/env bash
#SBATCH -J zj_n4_smoke
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 00:20:00
#SBATCH -o /data1/home/sunyiq/zhenjiang_oyv_v1/logs/n4_smoke_%j.out
#SBATCH -e /data1/home/sunyiq/zhenjiang_oyv_v1/logs/n4_smoke_%j.err
# Never write --mem on this platform.
#
# One task of the four-target ladder, epoch ceiling cut to one, into a throwaway
# output root. This exists to prove the chain runs on this platform before 1440
# tasks are committed to it. Its outputs are not scientific evidence and the
# root is deleted before the formal array.

set -eo pipefail          # never add -u

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source ${HOME}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "[FATAL] conda activate failed"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export PYTHONPATH="${ROOT}/pysite:${PYTHONPATH:-}"

echo "[INFO] node=$(hostname) job=${SLURM_JOB_ID}"
nvidia-smi --query-gpu=index,name,uuid,driver_version --format=csv,noheader || true

python - <<'PYCHK' || { echo "[FATAL] no usable GPU on $(hostname)"; exit 1; }
import sys, torch
sys.exit(0 if torch.cuda.is_available() else 1)
PYCHK

cd "${ROOT}/repo"
EXIT_CODE=0
python -u scripts/modeling/zhenjiang_oyv_n4_training.py \
    --task-index 0 \
    --output-root "${ROOT}/n4_smoke" \
    --device cuda:0 \
    --max-epochs 1 \
    || EXIT_CODE=$?

echo "[DONE] exit=${EXIT_CODE}"
exit ${EXIT_CODE}
