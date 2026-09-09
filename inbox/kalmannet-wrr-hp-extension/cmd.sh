#!/usr/bin/env bash
# Approved 21-task stage-B deployment; fresh stage-A admission and no retry enforced.
set -euo pipefail
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/model-selection20260908-stage-B-v1
cd "$PAYLOAD"
[[ ! -L launch.sh && -f launch.sh ]] || exit 1
printf '%s  launch.sh\n' b2ee899990b42a06436fb3afa5d415be0feaaa7cd141212a137b60ffb1361d7f | sha256sum -c -
bash -n "$PAYLOAD/launch.sh"
exec bash "$PAYLOAD/launch.sh"
