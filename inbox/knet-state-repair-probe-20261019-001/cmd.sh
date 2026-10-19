#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B "$PWD/inbox/knet-state-repair-probe-20261019-001/payload/deploy.py" "$PWD/inbox/knet-state-repair-probe-20261019-001/payload/package.tar.gz"
