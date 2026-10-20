#!/bin/bash
set -eo pipefail
date -u
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B "$HOME/hpc_mailbox/inbox/regge-pqx03-20261020/payload/submit.py" --archive "$HOME/hpc_mailbox/inbox/regge-pqx03-20261020/payload/training-v01.sealed" --sha256 0a36a68edd8a7f3d77ec3a5cfde043c0fcd76c76a5c8fb0d03f5309dcf261323 --plain-sha256 13488cc1e416026397667771d080f21eb53e7cf105987c4e28aa9811179e925b
