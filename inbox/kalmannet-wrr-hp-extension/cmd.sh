#!/usr/bin/env bash
# Approved18-task stage-A deployment; exclusive intent and no retry are enforced below.
set -euo pipefail
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/model-selection20260908-stage-A-v1
cd "$PAYLOAD"
printf '%s  launch.sh\n' c8a89f55de031979a3e0703202ffbf4bf7508090ae41d00d5e51daa861477ffe | sha256sum -c -
bash -n "$PAYLOAD/launch.sh"
exec bash "$PAYLOAD/launch.sh"
