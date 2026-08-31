#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf25_20260831
echo "=== ANCHOR JOB 216697 ==="
sacct -j 216697 -X --format=JobID%12,State%14,ExitCode%8,Elapsed%10 2>&1 || true
echo "=== ANCHOR RECORDS ==="
ls $ROOT/results/anchor/*.json 2>/dev/null | wc -l
echo "=== GATE VERDICT ==="
if [ -f $ROOT/results/anchor_gate_verdict.json ]; then
  python3 -c "
import json
v = json.load(open('$ROOT/results/anchor_gate_verdict.json'))
print('pass:', v['pass'], ' passed:', v['passed_count'], '/', v['required'])
d = v['anchor_deltas']
if d:
    mx = max(d.items(), key=lambda kv: kv[1])
    print('max_delta:', '%.3e' % mx[1], mx[0])
print('missing:', v['missing'])
"
else
  echo "VERDICT_NOT_YET"
fi
echo "=== ANCHOR LOG TAIL ==="
tail -6 $ROOT/logs/tukf25_anchor_*.out 2>/dev/null || true
tail -4 $ROOT/logs/tukf25_anchor_*.err 2>/dev/null || true
echo "SEQ2_OK"
