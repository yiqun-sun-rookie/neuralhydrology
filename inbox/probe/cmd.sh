#!/bin/bash
set -o pipefail
echo "=== STAGING kalmannet-tukf23 ==="
ls -la ~/.hpc_mailbox_staging/kalmannet-tukf23/ 2>&1 | tail -5
tail -c 1500 ~/.hpc_mailbox_staging/kalmannet-tukf23/result_4.txt 2>/dev/null || echo "no staged result_4"
echo "=== HUNG WORKERS for tukf23 ==="
ps -eo pid,ppid,etimes,stat,args 2>/dev/null | grep -E "cmd_4\.sh|kalmannet-tukf23" | grep -v grep || echo "none"
echo "=== ANCHOR JOB ==="
sacct -j 212954 -X --format=JobID%12,State%14,ExitCode%8,Elapsed%10 2>&1 | head -4
ls /data1/home/sunyiq/kalmannet_tukf23_20260826/results/anchor/ 2>/dev/null | wc -l
