#!/bin/bash
# READ-ONLY: final HPC state for the context-reset handoff.
set -o pipefail
date "+wallclock %F %T %z"
echo "=== A. MY QUEUE (any attrswap/fswap/pswap job still alive?) ==="
squeue -u "$USER" -o '%.11i %.26j %.9T %.10M %.9N' 2>&1 | grep -Ei 'attrswap|fswap|pswap|JOBID' || echo '  (none of this campaign queued or running)'
echo "=== B. LANDING DIRS ==="
for d in attr_swap_daily_2026_09 forcing_swap_daily_2026_09 precip_swap_daily_2026_09; do
  p=/data1/home/sunyiq/$d
  [ -d "$p" ] && echo "  $p : runs=$(ls $p/runs 2>/dev/null | wc -l) medians=$(ls $p/logs/*.public_median.txt 2>/dev/null | wc -l) size=$(du -sh $p 2>/dev/null | cut -f1)"
done
ls -d /data1/home/sunyiq/*_2026_09.* 2>/dev/null | sed 's/^/  旧副本: /'
echo "=== C. FINAL ACCOUNTING OF THE THREE CAMPAIGNS ==="
sacct -X -S 2026-09-05 -u "$USER" --format=JobID%9,JobName%26,State%12,Elapsed%10,Partition%7 2>&1 | grep -E "attrswap|fswap|pswap" | grep -vE "PENDING|RUNNING" | awk '{print "  "$0}' | tail -40
echo "=== D. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
