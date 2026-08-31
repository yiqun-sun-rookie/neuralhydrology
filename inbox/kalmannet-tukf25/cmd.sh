#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf25_20260831
echo "=== READOUT ARRAY 216851 STATES ==="
sacct -j 216851 --format=State --noheader 2>/dev/null | awk '{print $1}' | sort | uniq -c || true
echo "=== FAILURES ==="
sacct -j 216851 -X -n -P --format=JobID,State,ExitCode,Elapsed 2>/dev/null | grep -E '(FAILED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo "  none"
NJ=$(ls $ROOT/results/readout/*.json 2>/dev/null | wc -l)
NZ=$(ls $ROOT/results/readout/*.npz 2>/dev/null | wc -l)
echo "readout_json=$NJ readout_npz=$NZ"
[ "$NJ" = "108" ] && [ "$NZ" = "108" ] || { echo "NOT_COMPLETE_YET"; exit 0; }
echo "=== PACK AND PUSH READOUT RESULTS ==="
tar -czf /tmp/tukf25_readout_results_v1.tar.gz -C $ROOT/results readout
sha256sum /tmp/tukf25_readout_results_v1.tar.gz
cd ~/hpc_mailbox || exit 1
OK=""
for attempt in 1 2 3; do
  echo "--- push attempt $attempt ---"
  for i in $(seq 1 30); do [ -e .git/index.lock ] || break; sleep 2; done
  if [ -e .git/index.lock ]; then echo "lock still held"; sleep 10; continue; fi
  git fetch -q origin "+hpc-mailbox:refs/remotes/origin/hpc-mailbox" && \
  git reset -q --hard refs/remotes/origin/hpc-mailbox && \
  mkdir -p payload/kalmannet-tukf25 && \
  cp -f /tmp/tukf25_readout_results_v1.tar.gz payload/kalmannet-tukf25/ && \
  git add payload/kalmannet-tukf25/tukf25_readout_results_v1.tar.gz && \
  git commit -q -m "mailbox[kalmannet-tukf25]: readout results payload v1" && \
  git push -q origin HEAD:hpc-mailbox && OK=1 && break
  sleep 10
done
rm -f /tmp/tukf25_readout_results_v1.tar.gz
[ -n "$OK" ] && echo READOUT_PAYLOAD_PUSHED || { echo PAYLOAD_PUSH_FAILED; exit 1; }
