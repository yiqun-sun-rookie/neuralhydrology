#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf25_20260831
echo "=== TRAIN ARRAY 216699 STATES ==="
sacct -j 216699 --format=State --noheader 2>/dev/null | awk '{print $1}' | sort | uniq -c || true
echo "=== FAILURES ==="
sacct -j 216699 -X -n -P --format=JobID,State,ExitCode,Elapsed 2>/dev/null | grep -E '(FAILED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo "  none"
N=$(ls $ROOT/results/train/*.json 2>/dev/null | wc -l)
echo "train_records=$N"
[ "$N" = "108" ] || { echo "NOT_COMPLETE_YET"; exit 0; }
echo "=== SELECTED_UPDATE QUICK DIST ==="
python3 - <<'PYEOF'
import json, glob, collections
zeros = collections.Counter()
for p in glob.glob("/data1/home/sunyiq/kalmannet_tukf25_20260831/results/train/*.json"):
    r = json.load(open(p))
    if r["selected_update"] == 0:
        zeros[r["mode"]] += 1
print("selected_update==0 by mode:", dict(zeros))
PYEOF
echo "=== PACK AND PUSH TRAIN RESULTS ==="
tar -czf /tmp/tukf25_train_results_v1.tar.gz -C $ROOT/results train anchor anchor_gate_verdict.json
sha256sum /tmp/tukf25_train_results_v1.tar.gz
cd ~/hpc_mailbox || exit 1
OK=""
for attempt in 1 2 3; do
  echo "--- push attempt $attempt ---"
  for i in $(seq 1 30); do [ -e .git/index.lock ] || break; sleep 2; done
  if [ -e .git/index.lock ]; then echo "lock still held"; sleep 10; continue; fi
  git fetch -q origin "+hpc-mailbox:refs/remotes/origin/hpc-mailbox" && \
  git reset -q --hard refs/remotes/origin/hpc-mailbox && \
  mkdir -p payload/kalmannet-tukf25 && \
  cp -f /tmp/tukf25_train_results_v1.tar.gz payload/kalmannet-tukf25/ && \
  git add payload/kalmannet-tukf25/tukf25_train_results_v1.tar.gz && \
  git commit -q -m "mailbox[kalmannet-tukf25]: train results payload v1" && \
  git push -q origin HEAD:hpc-mailbox && OK=1 && break
  sleep 10
done
rm -f /tmp/tukf25_train_results_v1.tar.gz
[ -n "$OK" ] && echo TRAIN_PAYLOAD_PUSHED || { echo PAYLOAD_PUSH_FAILED; exit 1; }
