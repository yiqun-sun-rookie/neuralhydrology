#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B /data1/home/sunyiq/precip_smallfit_hpc_20261012_v01/20261016T145315Z_af5f130f_v04/payload/code/src/precip_input_assimilation/hpc/precip_smallfit_return_v01.py --root /data1/home/sunyiq/precip_smallfit_hpc_20261012_v01/20261016T145315Z_af5f130f_v04 --nonce af5f130f182c4c38ab020520c5374004
printf 'OPERATIONAL_QUEUE_ESTIMATE_BEGIN\n'
timeout 30 squeue --start -j 244110 2>&1 || true
timeout 30 scontrol show job 244110 -o 2>&1 || true
printf 'OPERATIONAL_QUEUE_ESTIMATE_END\n'
printf 'OWNED_QUEUE_RESOURCE_DIAGNOSIS_BEGIN\n'
printf '%s\n' 'READ_ONLY: squeue -p hgpu2p -t R,PD -h -o '"'"'%i|%j|%T|%l|%L|%R|%S|%p'"'"''
timeout 30 squeue -p hgpu2p -t R,PD -h -o '%i|%j|%T|%l|%L|%R|%S|%p' 2>&1 || true
printf 'OWNED_QUEUE_RESOURCE_DIAGNOSIS_END\n'
