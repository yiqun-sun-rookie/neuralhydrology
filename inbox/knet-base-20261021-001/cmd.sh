#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B "$PWD/inbox/knet-base-20261021-001/payload/export_missing_arrays.py"
