#!/usr/bin/env bash
# Authorized B activation recovery. Fresh A admission and exact once-only B guard remain.
set -euo pipefail
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/model-selection20260908-stage-B-v2
cd "$PAYLOAD"
[[ ! -L launch.sh && -f launch.sh ]] || exit 1
printf '%s  launch.sh\n' 902f01b4f2c0e43825d334f06f986cbc80270fea60345ccabffdb2fb43bc73b0 | sha256sum -c -
bash -n "$PAYLOAD/launch.sh"
exec bash "$PAYLOAD/launch.sh"
