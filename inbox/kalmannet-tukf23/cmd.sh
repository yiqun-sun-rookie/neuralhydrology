#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf23_20260826
echo "=== ARRAY 213224 STATE ==="
sacct -j 213224 -X -n --format=State%14 2>&1 | sort | uniq -c
echo "=== FAILURES ==="
sacct -j 213224 -X -n -P --format=JobID,State,ExitCode 2>&1 | grep -E 'FAILED|TIMEOUT|OUT_OF_MEM|NODE_FAIL' | head -8 || echo none
echo "=== TRAIN RECORDS ==="
ls $ROOT/results/train/ 2>/dev/null | wc -l
ls $ROOT/results/train/ 2>/dev/null | sed 's/^[0-9]*_//;s/\.json//' | sort | uniq -c
echo "=== ELAPSED SAMPLE ==="
sacct -j 213224_40,213224_80,213224_100 -X --format=JobID%14,State%12,Elapsed%10 2>&1 | tail -4
