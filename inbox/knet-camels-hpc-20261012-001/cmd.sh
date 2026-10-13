#!/bin/bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -B /data1/home/sunyiq/hpc_mailbox/inbox/knet-camels-hpc-20261012-001/payload/correction_effect_20261013_001/query_collect.py /data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/correction_effect_20261013_001 241629
