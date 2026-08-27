#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf24_20260827
echo "=== ARRAY STATE SUMMARY ==="
sacct -j 215316 --format=State --noheader 2>/dev/null | awk '{print $1}' | sort | uniq -c || true
echo "=== STILL QUEUED/RUNNING ==="
squeue -j 215316 2>/dev/null | head -6 || true
echo "=== TRAIN RECORDS COUNT ==="
ls $ROOT/results/train/*.json 2>/dev/null | wc -l
echo "=== NONZERO EXITS IF ANY ==="
sacct -j 215316 --format=JobID,State,ExitCode --noheader 2>/dev/null | grep -v "COMPLETED\|0:0" | head -10 || true
