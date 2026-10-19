#!/bin/bash
set -eo pipefail
export TZ=UTC
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B "$PWD/inbox/knet-state-repair-probe-20261019-001/payload/collect_submission_rejection.py" 245347
