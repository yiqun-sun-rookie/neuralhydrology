#!/usr/bin/env bash
# Read-only terminal audit with independently reviewed nonfinite-log encoding.
set -euo pipefail
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/model-selection20260908-audit-terminal-A-20260909-v1
cd "$PAYLOAD"
[[ ! -L launch.sh && -f launch.sh ]] || exit 1
printf '%s  launch.sh\n' 0ca8701d920c0ae57abec197471245a1e4d924e9d0c90848a6308dbe5179d332 | sha256sum -c -
exec bash "$PAYLOAD/launch.sh"
