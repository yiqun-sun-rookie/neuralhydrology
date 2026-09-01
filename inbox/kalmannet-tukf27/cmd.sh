#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf27_20260901
echo "=== READOUT 217822 ==="
sacct -j 217822 --format=State --noheader 2>/dev/null | awk '{print $1}' | sort | uniq -c || true
sacct -j 217822 -X -n -P --format=JobID,State,ExitCode 2>/dev/null | grep -E '(FAILED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo "  none"
NR=$(ls $ROOT/results/readout/*.json 2>/dev/null | wc -l)
NS=$(ls $ROOT/results/sim_readout/*.json 2>/dev/null | wc -l)
echo "da_readout=$NR/108 sim_readout=$NS/54"
[ "$NR" = "108" ] && [ "$NS" = "54" ] || { echo "NOT_COMPLETE_YET"; exit 0; }
echo "=== PACK ==="
tar -czf /tmp/tukf27_results_v1.tar.gz -C $ROOT/results train readout sim_readout prior_sim anchor anchor_gate_verdict.json
sha256sum /tmp/tukf27_results_v1.tar.gz
cd ~/hpc_mailbox || exit 1
OK=""
for attempt in 1 2 3; do
  for i in $(seq 1 30); do [ -e .git/index.lock ] || break; sleep 2; done
  git fetch -q origin "+hpc-mailbox:refs/remotes/origin/hpc-mailbox" && \
  git reset -q --hard refs/remotes/origin/hpc-mailbox && \
  mkdir -p payload/kalmannet-tukf27 && \
  cp -f /tmp/tukf27_results_v1.tar.gz payload/kalmannet-tukf27/ && \
  git add payload/kalmannet-tukf27/tukf27_results_v1.tar.gz && \
  git commit -q -m "mailbox[kalmannet-tukf27]: results payload v1" && \
  git push -q origin HEAD:hpc-mailbox && OK=1 && break
  sleep 10
done
rm -f /tmp/tukf27_results_v1.tar.gz
[ -n "$OK" ] && echo RESULTS_PUSHED || { echo PUSH_FAILED; exit 1; }
