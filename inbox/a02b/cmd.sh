#!/bin/bash
# a02b seq=1 : hardened status check. Every call bounded by timeout.
export LC_ALL=C
PKG=/data1/home/$USER/nature_1st_a02

echo "=== A QUEUE ==="
timeout 25 squeue -u "$USER" -o "%.10i %.16j %.8T %.10M %.14R" 2>&1 | grep -E "a02_|JOBID"

echo "=== B ACCOUNTING ==="
timeout 40 sacct -S 2026-08-07 -u "$USER" -X --format=JobID%9,JobName%13,State%11,ExitCode%7,Elapsed%9 2>&1 | grep -E "a02_(pre|sam)|JobID|----"

echo "=== C EPOCH COUNTS ==="
timeout 30 bash -c '
for f in '"$PKG"'/logs/a02_*.out; do
  [ -f "$f" ] || continue
  printf "  %-24s lines=%-7s %s\n" "$(basename $f .out)" "$(wc -l < $f)" "$(tail -c 4000 $f | grep -a "^Epoch" | tail -1 | cut -c1-70)"
done' 2>&1

echo "=== D TARBALLS ==="
timeout 20 ls -la /data1/home/$USER/hpc_mailbox/outbox/a02_*.tar.gz 2>&1 | awk '{print "  ",$9,$5}'

echo "=== E STUCK a02 WORKER ==="
timeout 15 ps -u "$USER" -o pid,etime,stat,cmd 2>&1 | grep -E "cmd_18|a02" | grep -v grep | head -5
