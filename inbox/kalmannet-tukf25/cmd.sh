#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf25_20260831
echo "=== TRAIN ARRAY 216699 STATES ==="
sacct -j 216699 --format=State --noheader 2>/dev/null | awk '{print $1}' | sort | uniq -c || true
echo "=== TRAIN RECORDS ==="
ls $ROOT/results/train/*.json 2>/dev/null | wc -l
echo "=== FAILURES (never truncate) ==="
sacct -j 216699 -X -n -P --format=JobID,State,ExitCode,Elapsed 2>/dev/null | grep -E '(FAILED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo "  none"
echo "=== SAMPLE ERR TAIL ==="
E=$(ls -t $ROOT/logs/tukf25_train_*.err 2>/dev/null | head -1)
[ -n "$E" ] && tail -3 "$E" || echo "no err files yet"
echo "SEQ4_OK"
