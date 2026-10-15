#!/bin/bash
set -o pipefail
# READ-ONLY on ~/neuralhydrology: SHA-256 manifest of the CAMELS-US files the ID18 protocol reads (writes only into own ROOT)
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
P="$HOME/hpc_mailbox/inbox/openhydronet-531-20261015/payload/v2"
date --iso-8601=seconds
D=$(readlink -f "$HOME/neuralhydrology/data/camels_us"); echo "camels_us -> $D"
ls "$D" | head -12
ls "$D/basin_mean_forcing" 2>&1 | head
mkdir -p "$ROOT/manifests"
source ~/miniconda3/etc/profile.d/conda.sh; conda activate nh_final || exit 1
python "$P/manifest_camels.py" "$D" "$P/conceptual_benchmark_camels_us_531_repro.txt" "$ROOT/manifests/camels_us_hpc.tsv"
exit 0
