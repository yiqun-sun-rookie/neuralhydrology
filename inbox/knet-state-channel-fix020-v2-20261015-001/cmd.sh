#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B "$PWD/inbox/knet-state-channel-fix020-v2-20261015-001/payload/deploy_recovery_v2.py" "$PWD/inbox/knet-state-channel-fix020-v2-20261015-001/payload/package.tar.gz"
