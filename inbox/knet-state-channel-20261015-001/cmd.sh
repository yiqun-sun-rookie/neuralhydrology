#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B "$PWD/inbox/knet-state-channel-20261015-001/payload/deploy.py" "$PWD/inbox/knet-state-channel-20261015-001/payload/package.tar.gz"
