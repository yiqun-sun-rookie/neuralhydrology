#!/usr/bin/env bash
set -eo pipefail
payload=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928
bash "$payload/submit_original_eight.sh"
bash "$payload/retrieve_adaptive_test_preflight.sh"
