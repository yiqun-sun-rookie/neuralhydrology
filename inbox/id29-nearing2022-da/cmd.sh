#!/bin/bash
# ID29 seq=48: read-only status and artifact check for three-arm comparison job 202159.
ROOT=/data1/home/sunyiq/nearing2022_da

echo "=== ACCOUNTING ==="
sacct -j 202159 -X --format=JobID%10,JobName%14,State%12,ExitCode%8,Elapsed%10 2>&1

echo "=== STDOUT ==="
tail -80 "$ROOT/logs/compare_202159.out" 2>/dev/null

echo "=== STDERR ==="
tail -40 "$ROOT/logs/compare_202159.err" 2>/dev/null

echo "=== HEADLINE TABLE ==="
cat "$ROOT/results/29_nearing2022_da_ar/headline_table.csv" 2>/dev/null
