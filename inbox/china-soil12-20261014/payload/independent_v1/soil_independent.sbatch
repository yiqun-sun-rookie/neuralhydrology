#!/bin/bash
#SBATCH --job-name=china_soil_missing12_independent
#SBATCH --partition=hgpu2p
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --exclude=ngu002
#SBATCH --time=00:20:00
#SBATCH --no-requeue
#SBATCH --chdir=/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/independent_v1
#SBATCH --output=/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/independent_v1/logs/independent-%j.out
#SBATCH --error=/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/independent_v1/logs/independent-%j.err
set -eo pipefail
test -n "$SLURM_JOB_ID"
test "${SLURM_RESTART_COUNT:-0}" = 0
export CUDA_VISIBLE_DEVICES='' PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1
export PYTHONPATH=/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/deps_v2
export GDAL_CACHEMAX=64
ulimit -v 2097152
ulimit -f 131072
timeout --signal=TERM --kill-after=5s 1170s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -u independent_recompute.py
