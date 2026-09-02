#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf28_20260902
JOB=218826

echo "=== WAIT FOR READOUT ARRAY $JOB (max 60 min) ==="
for i in $(seq 1 60); do
  R=$(squeue -j $JOB -h -o "%T" 2>/dev/null | wc -l)
  [ "$R" -eq 0 ] && break
  sleep 60
done
sacct -j $JOB -n -P -X --format=State 2>/dev/null | sed 's/ .*//' | sort | uniq -c
sacct -j $JOB -n -P -X --format=JobID,State,ExitCode 2>/dev/null \
  | grep -E "FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL" | head -10

echo "=== COUNTS ==="
echo "readout_json=$(ls $ROOT/results/readout/*.json 2>/dev/null | wc -l) / 189"
echo "readout_npz=$(ls $ROOT/results/readout/*.npz 2>/dev/null | wc -l) / 189"
echo "train_json=$(ls $ROOT/results/train/*.json 2>/dev/null | wc -l) / 189"

echo "=== BASELINE RE-READ SELF-CHECK ==="
python - <<'PY'
import glob, json
rows = [json.load(open(p)) for p in glob.glob(
    '/data1/home/sunyiq/kalmannet_tukf28_20260902/results/readout/*.json')]
agg = {}
for r in rows:
    d = r.get('baseline_relative_deviation')
    if d is None: continue
    a = agg.setdefault(r['mode'], {'max': 0.0, 'kinds': {}})
    a['max'] = max(a['max'], d)
    a['kinds'][r['baseline_reproduction']] = a['kinds'].get(r['baseline_reproduction'], 0) + 1
for m in sorted(agg):
    print('  %-20s max_dev=%.3e  %s' % (m, agg[m]['max'], agg[m]['kinds']))
print('  cells with a baseline check: %d' % sum(sum(a['kinds'].values()) for a in agg.values()))
PY

echo "=== PACK ==="
tar -czf /tmp/tukf28_results_v1.tar.gz -C $ROOT/results train readout anchor anchor_gate_verdict.json || exit 1
sha256sum /tmp/tukf28_results_v1.tar.gz
cd ~/hpc_mailbox || exit 1
OK=""
for attempt in 1 2 3; do
  for i in $(seq 1 30); do [ -e .git/index.lock ] || break; sleep 2; done
  git fetch -q origin "+hpc-mailbox:refs/remotes/origin/hpc-mailbox" && \
  git reset -q --hard refs/remotes/origin/hpc-mailbox && \
  mkdir -p payload/kalmannet-tukf28 && \
  cp -f /tmp/tukf28_results_v1.tar.gz payload/kalmannet-tukf28/ && \
  git add payload/kalmannet-tukf28/tukf28_results_v1.tar.gz && \
  git commit -q -m "mailbox[kalmannet-tukf28]: results payload v1" && \
  git push -q origin HEAD:hpc-mailbox && OK=1 && break
  sleep 10
done
rm -f /tmp/tukf28_results_v1.tar.gz
[ -n "$OK" ] && echo RESULTS_PUSHED || { echo PUSH_FAILED; exit 1; }
echo SEQ5_OK
