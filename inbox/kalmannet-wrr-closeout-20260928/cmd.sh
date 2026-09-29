#!/usr/bin/env bash
set -eo pipefail
bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/read_corrected_array_audit.sh
bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/retrieve_paired_sampling.sh 800
bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/retrieve_paired_sampling.sh domain
