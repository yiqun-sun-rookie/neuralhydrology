#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -X utf8 -B /data1/home/sunyiq/kalmannet_original_noise_multiday_20261008_recovery1/code/remote.py export --start 0 --stop 100 --chunk 0
