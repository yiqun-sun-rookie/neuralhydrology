#!/bin/bash
set -eo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B /data1/home/sunyiq/kalmannet_tukf09_four_failed_basins_20261003_attempt1/remote_stage.py collect 02202600
