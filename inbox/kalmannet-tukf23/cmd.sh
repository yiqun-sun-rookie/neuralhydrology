#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf23_20260826
echo "=== PACK READOUT RESULTS ==="
NJ=$(ls $ROOT/results/readout/*.json 2>/dev/null | wc -l)
NZ=$(ls $ROOT/results/readout/*.npz 2>/dev/null | wc -l)
echo "json=$NJ npz=$NZ"
[ "$NJ" = "108" ] && [ "$NZ" = "108" ] || { echo "NOT_COMPLETE"; exit 1; }
tar -czf /tmp/tukf23_readout_results_v2.tar.gz -C $ROOT/results readout
sha256sum /tmp/tukf23_readout_results_v2.tar.gz
cd ~/hpc_mailbox || exit 1
git fetch -q origin "+hpc-mailbox:refs/remotes/origin/hpc-mailbox" && \
git reset -q --hard refs/remotes/origin/hpc-mailbox && \
cp -f /tmp/tukf23_readout_results_v2.tar.gz payload/kalmannet-tukf23/ && \
git add payload/kalmannet-tukf23/tukf23_readout_results_v2.tar.gz && \
git commit -q -m "mailbox[kalmannet-tukf23]: readout results payload v2" && \
git push -q origin HEAD:hpc-mailbox && echo READOUT_PAYLOAD_PUSHED || echo PAYLOAD_PUSH_FAILED
rm -f /tmp/tukf23_readout_results_v2.tar.gz
