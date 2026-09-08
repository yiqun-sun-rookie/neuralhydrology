#!/usr/bin/env bash
# Read-only observation with complete scheduler and post-query failure history.
set -euo pipefail
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/model-selection20260908-audit-observer-v3
cd "$PAYLOAD"
[[ ! -L launch.sh && -f launch.sh ]] || exit 1
printf '%s  launch.sh\n' 3a495f538a64a45bfcc681a76a9dcee5fea165b054d1238a34d1345991229675 | sha256sum -c -
exec bash "$PAYLOAD/launch.sh"
