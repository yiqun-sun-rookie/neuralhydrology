#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python -X utf8 -B /data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261009_recovery5/code/remote.py export --start 100 --stop 200 --chunk 6
