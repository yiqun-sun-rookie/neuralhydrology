#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B "$PWD/inbox/knet-camels-hpc-20261012-001/payload/020_ablation_deploy.py" "$PWD/inbox/knet-camels-hpc-20261012-001/payload/020_ablation.tar.gz"
