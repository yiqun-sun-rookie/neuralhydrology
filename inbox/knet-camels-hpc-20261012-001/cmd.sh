#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B "$PWD/inbox/knet-camels-hpc-20261012-001/payload/recheck3_deploy.py" "$PWD/inbox/knet-camels-hpc-20261012-001/payload/recheck3.tar.gz"
