#!/bin/bash
# Collect the sixteen replay verdicts.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
echo "=== WAIT FOR ARRAY 215161 (max 20 min) ==="
for i in $(seq 1 120); do
  LEFT=$(sacct -j 215161 -X -n -o State 2>/dev/null | grep -cE 'RUNNING|PENDING' || true)
  [ "$LEFT" -eq 0 ] && { echo "  settled t=$((i*10))s"; break; }
  [ $((i % 18)) -eq 0 ] && echo "  t=$((i*10))s left=$LEFT"
  sleep 10
done
sacct -j 215161 -X -n -P -o State 2>/dev/null | sort | uniq -c | sed 's/^/  /'
echo "=== SHARD VERDICTS ==="
TOTAL_REPLAYED=0; TOTAL_MISMATCH=0; SHARDS_OK=0
for i in $(seq 0 15); do
  f="$ROOT/n4_audit_replay_$i/audit_summary.json"
  if [ -f "$f" ]; then
    V=$(python -c "import json;d=json.load(open('$f'));print(d['verdict'],d['tasks_replayed'],d['mismatch_count'])" 2>/dev/null)
    echo "  shard $i: $V"
    set -- $V
    [ "$1" = "reproducible" ] && SHARDS_OK=$((SHARDS_OK+1))
    TOTAL_REPLAYED=$((TOTAL_REPLAYED+${2:-0})); TOTAL_MISMATCH=$((TOTAL_MISMATCH+${3:-0}))
  else
    echo "  shard $i: NO SUMMARY"
  fi
done
echo "SHARDS_REPRODUCIBLE=$SHARDS_OK/16 TOTAL_REPLAYED=$TOTAL_REPLAYED TOTAL_MISMATCH=$TOTAL_MISMATCH"
echo "=== ANY MISMATCH DETAIL ==="
for i in $(seq 0 15); do
  f="$ROOT/n4_audit_replay_$i/audit_mismatches.csv"
  [ -f "$f" ] && [ "$(wc -l < "$f")" -gt 1 ] && { echo "  -- shard $i --"; head -5 "$f" | sed 's/^/    /'; }
done
echo "  (none printed = clean)"
echo "=== DONE ==="
