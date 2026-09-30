#!/bin/bash
# Read-only transfer of three existing models; no jobs and no writes to model roots.
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B /data1/home/sunyiq/hpc_mailbox/inbox/attrswap-daily/payload/china2023_20260930/retrieve_models.py
