#!/usr/bin/env bash
set -eo pipefail
sinfo -p hgpu2p -N -O nodelist,gres:14,gresused:24,cpusstate
bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/submit_completed_ten.sh a1536ae972f96def201563683f04ce57112801b8c3161e2139270d16289c39e3
