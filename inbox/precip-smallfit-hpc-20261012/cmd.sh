#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B /data1/home/sunyiq/precip_smallfit_hpc_20261012_v01/20261015T062534Z_26ac3faf_v03/payload/code/src/precip_input_assimilation/hpc/precip_smallfit_return_v01.py --root /data1/home/sunyiq/precip_smallfit_hpc_20261012_v01/20261015T062534Z_26ac3faf_v03 --nonce 26ac3faff4e34c7ba4eea6e485377376
printf 'OPERATIONAL_QUEUE_ESTIMATE_BEGIN\n'
timeout 30 squeue --start -j 242770 2>&1 || true
timeout 30 scontrol show job 242770 -o 2>&1 || true
printf 'OPERATIONAL_QUEUE_ESTIMATE_END\n'
