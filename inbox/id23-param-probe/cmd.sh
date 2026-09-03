#!/bin/bash
# Retry artifact retrieval under outbox/<ch>/artifacts/ (payload/ dirs are not committed by the runner).
set -o pipefail
ROOT=/data1/home/sunyiq/id23_param_probe
OUT=~/hpc_mailbox/outbox/id23-param-probe/artifacts
mkdir -p "$OUT"
tar czf "$OUT/parameter_axis_probe_v01_out_20260903.tar.gz" -C "$ROOT" out
sha256sum "$OUT/parameter_axis_probe_v01_out_20260903.tar.gz" | tee "$OUT/parameter_axis_probe_v01_out_20260903.tar.gz.sha256"
ls -la "$OUT"
rm -rf ~/hpc_mailbox/outbox/id23-param-probe/payload
