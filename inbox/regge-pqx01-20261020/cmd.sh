#!/bin/bash
set -eo pipefail
date -u
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B "$HOME/hpc_mailbox/inbox/regge-pqx01-20261020/payload/submit.py" --archive "$HOME/hpc_mailbox/inbox/regge-pqx01-20261020/payload/payload-v02.sealed" --sha256 a149f756fb5d4e57bf44ed3839ea40eed85513d79933307f74c7bcfc5d97271a --plain-sha256 042c260182cbc7c2a68e0ea223d608d60e24fd4630971daa59793139a3d4ad7e
