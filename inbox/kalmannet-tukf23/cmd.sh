#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf23_20260826
echo "=== PACK TRAIN RESULTS ==="
cd $ROOT || exit 1
tar -czf /tmp/tukf23_train_results_v2.tar.gz -C $ROOT/results train anchor
sha256sum /tmp/tukf23_train_results_v2.tar.gz
echo "=== COMMIT PAYLOAD BACK ==="
cd ~/hpc_mailbox || exit 1
git fetch -q origin "+hpc-mailbox:refs/remotes/origin/hpc-mailbox" && \
git reset -q --hard refs/remotes/origin/hpc-mailbox && \
mkdir -p payload/kalmannet-tukf23 && \
cp -f /tmp/tukf23_train_results_v2.tar.gz payload/kalmannet-tukf23/ && \
git add payload/kalmannet-tukf23/tukf23_train_results_v2.tar.gz && \
git commit -q -m "mailbox[kalmannet-tukf23]: train results payload v2" && \
git push -q origin HEAD:hpc-mailbox && echo PAYLOAD_PUSHED || echo PAYLOAD_PUSH_FAILED
rm -f /tmp/tukf23_train_results_v2.tar.gz
