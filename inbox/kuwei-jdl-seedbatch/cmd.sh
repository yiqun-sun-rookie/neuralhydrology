#!/bin/bash
# Read-only status query for the anchor decomposition job 216698. No submission, no waiting.
set -o pipefail
ROOT=$HOME/kuwei_jdl_seedbatch_20260831
echo "=== A. sacct ==="
sacct -j 216698 --format=JobID%14,JobName%18,Partition%14,State%20,ExitCode%9,Start%20,End%20,Elapsed%12 2>&1 | head -6 || true
echo "=== B. squeue ==="
squeue -u ${USER} -n kuwei-jdl-anchor -o "%.10i %.18j %.14P %.10T %R" 2>&1 | head -4 || true
echo "=== C. stdout tail ==="
tail -30 $ROOT/logs/kuwei-jdl-anchor-216698.out 2>&1 || true
echo "=== D. stderr tail ==="
tail -12 $ROOT/logs/kuwei-jdl-anchor-216698.err 2>&1 || true
echo "=== E. decomposition json ==="
cat $ROOT/out/anchor_hpc/anchor_decomposition.json 2>&1 || true
echo "=== DONE ==="
