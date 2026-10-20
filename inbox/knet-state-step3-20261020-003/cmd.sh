#!/bin/bash
set -eo pipefail
export TZ=UTC
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B /data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_step3_replay_20261020_003/collect_terminal.py 0
