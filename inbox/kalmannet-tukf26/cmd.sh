#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf26_20260831
echo "=== READOUT 217426 ==="
sacct -j 217426 --format=State --noheader 2>/dev/null | awk '{print $1}' | sort | uniq -c || true
sacct -j 217426 -X -n -P --format=JobID,State,ExitCode 2>/dev/null | grep -E '(FAILED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo "  none"
NJ=$(ls $ROOT/results/readout/*.json 2>/dev/null | wc -l); NZ=$(ls $ROOT/results/readout/*.npz 2>/dev/null | wc -l)
echo "readout_json=$NJ readout_npz=$NZ / 135"
[ "$NJ" = "135" ] && [ "$NZ" = "135" ] || { echo "NOT_COMPLETE_YET"; exit 0; }
echo "=== PACK AND PUSH ==="
tar -czf /tmp/tukf26_results_v1.tar.gz -C $ROOT/results train readout anchor anchor_gate_verdict.json
sha256sum /tmp/tukf26_results_v1.tar.gz
cd ~/hpc_mailbox || exit 1
OK=""
for attempt in 1 2 3; do
  for i in $(seq 1 30); do [ -e .git/index.lock ] || break; sleep 2; done
  git fetch -q origin "+hpc-mailbox:refs/remotes/origin/hpc-mailbox" && \
  git reset -q --hard refs/remotes/origin/hpc-mailbox && \
  mkdir -p payload/kalmannet-tukf26 && \
  cp -f /tmp/tukf26_results_v1.tar.gz payload/kalmannet-tukf26/ && \
  git add payload/kalmannet-tukf26/tukf26_results_v1.tar.gz && \
  git commit -q -m "mailbox[kalmannet-tukf26]: results payload v1" && \
  git push -q origin HEAD:hpc-mailbox && OK=1 && break
  sleep 10
done
rm -f /tmp/tukf26_results_v1.tar.gz
[ -n "$OK" ] && echo RESULTS_PUSHED || { echo PUSH_FAILED; exit 1; }
