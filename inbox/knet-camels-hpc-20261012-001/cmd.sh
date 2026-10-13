#!/bin/bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -B "$PWD/inbox/knet-camels-hpc-20261012-001/payload/origins_041_20261013_001_deploy.py" "$PWD/inbox/knet-camels-hpc-20261012-001/payload/origins_041_20261013_001.tar.gz"
