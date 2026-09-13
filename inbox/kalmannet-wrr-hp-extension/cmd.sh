#!/usr/bin/env bash
# Read-only combined stage-B terminal audit collector (original 224255 + retry1 224389 + retry2 225178).
set -euo pipefail
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/model-selection20260908-audit-terminal-B-combined-20260913-v1
cd "$PAYLOAD"
[[ ! -L launch.sh && -f launch.sh ]] || exit 1
printf '%s  launch.sh\n' f0980bbc19f0c8deed46991fb4f9eb905ee32010948fec2efa6e3bb4d84b22f8 | sha256sum -c -
exec bash "$PAYLOAD/launch.sh"
