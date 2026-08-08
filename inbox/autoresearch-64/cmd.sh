#!/bin/bash
R=~/autoresearch64/runs/unified_autoresearch/hbv_lite_64_hpc_v4/runs/forward/train
echo "=== deny lines in the access log ==="
grep '"decision":"deny"' $R/logs/access.jsonl 2>/dev/null | head -5
echo "=== last 8 events before the end ==="
tail -8 $R/logs/access.jsonl 2>/dev/null
echo "=== runtime result ==="
cat $R/logs/runtime-result.json 2>/dev/null
echo "=== dependency preflight decision ==="
python -c "import json;d=json.load(open('$R/logs/dependency-preflight.json'));print('decision:',d.get('decision'));[print(' ',m['declaration'],'active',m.get('active_version'),'installed',m.get('installed_versions'),'matched',m.get('matched')) for m in d.get('matches',[])]" 2>&1 | head -8
echo "=== candidate stderr ==="
cat $R/logs/stderr.txt 2>/dev/null | tail -20
