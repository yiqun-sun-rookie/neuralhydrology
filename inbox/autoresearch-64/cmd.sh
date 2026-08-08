#!/bin/bash
ROOT=~/autoresearch64
R=$ROOT/runs/unified_autoresearch/hbv_lite_64_hpc_v2/runs/forward/train
echo "=== A. what does the run record say? ==="
find $R -maxdepth 2 -name "*.json" | head -10
for f in $R/runtime-result.json $R/logs/runtime-result.json $R/resource-preflight.json $R/dependency-preflight.json; do
  [ -f "$f" ] && { echo "--- $f ---"; head -60 "$f"; }
done
echo "=== B. candidate stderr / stdout ==="
find $R -name "*.log" -o -name "stderr*" -o -name "stdout*" | head -10
for f in $(find $R -name "stderr*" -o -name "*.err" | head -3); do echo "--- $f ---"; tail -30 "$f"; done
echo "=== C. access log (what was denied?) ==="
tail -20 $R/logs/access.jsonl 2>/dev/null
echo "=== D. full log dir listing ==="
ls -la $R/logs/ 2>/dev/null | head -15
ls -la $R/ 2>/dev/null | head -15
