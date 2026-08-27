#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf24_20260827
echo "=== REPACK TRAIN RESULTS ==="
NJ=$(ls $ROOT/results/train/*.json 2>/dev/null | wc -l)
NA=$(ls $ROOT/results/anchor/*.json 2>/dev/null | wc -l)
echo "train_json=$NJ anchor_json=$NA"
[ "$NJ" = "108" ] && [ "$NA" = "27" ] || { echo "NOT_COMPLETE"; exit 1; }
tar -czf /tmp/tukf24_train_results_v1.tar.gz -C $ROOT/results train anchor
sha256sum /tmp/tukf24_train_results_v1.tar.gz
cd ~/hpc_mailbox || exit 1
OK=""
for attempt in 1 2 3; do
  echo "--- push attempt $attempt ---"
  for i in $(seq 1 30); do [ -e .git/index.lock ] || break; sleep 2; done
  if [ -e .git/index.lock ]; then echo "lock still held"; sleep 10; continue; fi
  git fetch -q origin "+hpc-mailbox:refs/remotes/origin/hpc-mailbox" && \
  git reset -q --hard refs/remotes/origin/hpc-mailbox && \
  cp -f /tmp/tukf24_train_results_v1.tar.gz payload/kalmannet-tukf24/ && \
  git add payload/kalmannet-tukf24/tukf24_train_results_v1.tar.gz && \
  git commit -q -m "mailbox[kalmannet-tukf24]: train results payload v1 (retry)" && \
  git push -q origin HEAD:hpc-mailbox && OK=1 && break
  sleep 10
done
[ -n "$OK" ] && echo TRAIN_PAYLOAD_PUSHED || echo PAYLOAD_PUSH_FAILED
rm -f /tmp/tukf24_train_results_v1.tar.gz
[ -n "$OK" ]
