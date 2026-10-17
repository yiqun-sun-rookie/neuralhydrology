#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export CUDA_VISIBLE_DEVICES=""
cd /data1/home/sunyiq/zhenjiang_sqrt_covariance_repair_20261017_001
python -B hpc/gpu_workflow.py probe
