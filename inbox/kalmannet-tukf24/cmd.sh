#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf24_20260827
echo "=== READOUT ARRAYS STATE ==="
sacct -j 215433,215434 --format=State --noheader 2>/dev/null | awk '{print $1}' | sort | uniq -c || true
echo "=== COUNTS ==="
NN=$(ls $ROOT/results/readout_new/*.json 2>/dev/null | wc -l)
NZ=$(ls $ROOT/results/readout_new/*.npz 2>/dev/null | wc -l)
ON=$(ls $ROOT/results/readout_old/*.json 2>/dev/null | wc -l)
OZ=$(ls $ROOT/results/readout_old/*.npz 2>/dev/null | wc -l)
echo "new_json=$NN new_npz=$NZ old_json=$ON old_npz=$OZ"
[ "$NN" = "108" ] && [ "$NZ" = "108" ] && [ "$ON" = "108" ] && [ "$OZ" = "108" ] || { echo "NOT_COMPLETE_YET"; exit 1; }
echo "=== PACK AND PUSH ==="
tar -czf /tmp/tukf24_readout_results_v1.tar.gz -C $ROOT/results readout_new readout_old
sha256sum /tmp/tukf24_readout_results_v1.tar.gz
cd ~/hpc_mailbox || exit 1
OK=""
for attempt in 1 2 3; do
  echo "--- push attempt $attempt ---"
  for i in $(seq 1 30); do [ -e .git/index.lock ] || break; sleep 2; done
  if [ -e .git/index.lock ]; then echo "lock still held"; sleep 10; continue; fi
  git fetch -q origin "+hpc-mailbox:refs/remotes/origin/hpc-mailbox" && \
  git reset -q --hard refs/remotes/origin/hpc-mailbox && \
  cp -f /tmp/tukf24_readout_results_v1.tar.gz payload/kalmannet-tukf24/ && \
  git add payload/kalmannet-tukf24/tukf24_readout_results_v1.tar.gz && \
  git commit -q -m "mailbox[kalmannet-tukf24]: readout results payload v1" && \
  git push -q origin HEAD:hpc-mailbox && OK=1 && break
  sleep 10
done
[ -n "$OK" ] && echo READOUT_PAYLOAD_PUSHED || echo PAYLOAD_PUSH_FAILED
rm -f /tmp/tukf24_readout_results_v1.tar.gz
[ -n "$OK" ]
