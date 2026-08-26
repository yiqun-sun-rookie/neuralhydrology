#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf23_20260826
echo "=== tukf23 STAGING ==="
ls -la ~/.hpc_mailbox_staging/kalmannet-tukf23/ 2>&1 | tail -4
tail -c 900 ~/.hpc_mailbox_staging/kalmannet-tukf23/result_15.txt 2>/dev/null || echo "no staged result_15"
echo "=== READOUT JOB ==="
sacct -j 213487 -X -n --format=State%14 2>&1 | sort | uniq -c
echo "=== READOUT FILES ==="
ls $ROOT/results/readout/*.json 2>/dev/null | wc -l
ls $ROOT/results/readout/*.npz 2>/dev/null | wc -l
echo "=== WORKERS ==="
ps -eo pid,etimes,args 2>/dev/null | grep -E "cmd_15|kalmannet-tukf23" | grep -v grep || echo none
