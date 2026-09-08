#!/usr/bin/env bash
set -euo pipefail
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/model-selection20260908-stage-A-v1
cd "$PAYLOAD"
printf '%s  deploy.sh\n' 184cd7778cbb7545f6fd8cfdbf91e28f8c3baba1c0b612c2e61b02d5f9c8c197 | sha256sum -c -
exec bash "$PAYLOAD/deploy.sh" "$PAYLOAD" 11b79c2ff04630e658443f51c968ab7f69bc1500598af713b4e4990f86586923
