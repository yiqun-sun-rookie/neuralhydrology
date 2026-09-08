#!/usr/bin/env bash
# One read-only audit observation, not a training or admission command.
set -euo pipefail
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/model-selection20260908-audit-observer-v1
cd "$PAYLOAD"
[[ ! -L launch.sh && -f launch.sh ]] || exit 1
printf '%s  launch.sh\n' 5589bc73d146d10a7848b21163462f9a3dbeedc926ac48aeb7363b2d15fc6551 | sha256sum -c -
exec bash "$PAYLOAD/launch.sh"
