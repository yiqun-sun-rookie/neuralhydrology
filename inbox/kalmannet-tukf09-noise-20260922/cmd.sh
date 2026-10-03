#!/bin/bash
set -eo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B /data1/home/sunyiq/kalmannet_tukf09_four_failed_basins_20261003_attempt1/remote_stage.py admit 02202600 --audit-sha ceeffc0d4028a9929d074332bd2bfa248896e7079eb1c12b42f5f66f157202d1 --capture-sha c1f814b0add1e79c4a87c5186dccb9a5c02a5a7d7ad358b13122473a92ba0338
