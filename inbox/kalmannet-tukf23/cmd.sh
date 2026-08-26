#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf23_20260826
echo "=== ARRAY 213224 STATE ==="
sacct -j 213224 -X -n --format=State%14 2>&1 | sort | uniq -c
echo "=== EARLY FAILURES ==="
sacct -j 213224 -X -n -P --format=JobID,State,ExitCode 2>&1 | grep -E 'FAILED|TIMEOUT|OUT_OF_MEM|NODE_FAIL' | head -5 || echo none
echo "=== ERR SAMPLE (first trainable) ==="
tail -12 $ROOT/logs/tukf23_train_213224_27.err 2>/dev/null | tail -8 || echo "no err content"
echo "=== OUT SAMPLE ==="
tail -3 $ROOT/logs/tukf23_train_213224_27.out 2>/dev/null || echo "no out"
echo "=== TRAIN RECORDS ==="
ls $ROOT/results/train/ 2>/dev/null | wc -l
