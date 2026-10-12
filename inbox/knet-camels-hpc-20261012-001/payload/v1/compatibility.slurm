#!/bin/bash
#SBATCH -J knet_camels_import_261012
#SBATCH -p hgpu4
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=1
#SBATCH -t 00:05:00
#SBATCH --no-requeue
#SBATCH -o /data1/home/sunyiq/knet_camels_hpc_20261012_001/logs/compatibility-%j.out
#SBATCH -e /data1/home/sunyiq/knet_camels_hpc_20261012_001/logs/compatibility-%j.err
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
export PYTHONUTF8=1
export ATEN_CPU_CAPABILITY=default
unset PYTHONPATH
cd /data1/home/sunyiq/knet_camels_hpc_20261012_001
python -u -B /data1/home/sunyiq/knet_camels_hpc_20261012_001/probe_report.py
scontrol show job "$SLURM_JOB_ID"
