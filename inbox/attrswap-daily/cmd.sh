#!/bin/bash
# USER-AUTHORIZED 2026-09-11 ("ALL"): isolate the 3 cancelled era5l arms in the precip_swap landing point
# by RENAMING them to INCOMPLETE_ABORTED_<orig> (same names as the local mirror). Rename only, nothing deleted.
# Closes HANDOFF_20260911 section 8 item "3 个错误臂目录改名隔离". No sbatch, no other writes.
set -o pipefail
date "+wallclock %F %T %z"
P=/data1/home/sunyiq/precip_swap_daily_2026_09
echo "=== A. MY QUEUE (must be empty of this campaign; header must be visible) ==="
squeue -u "$USER" -o '%.11i %.26j %.9T %.10M %.9N' 2>&1 | grep -Ei 'attrswap|fswap|pswap|JOBID'
echo "  squeue rc=${PIPESTATUS[0]}"
echo "=== B. BEFORE ==="
ls -l --time-style=+%F_%T $P/runs 2>&1 | grep -v '^total' | awk '{print "  "$6"  "$7}'
echo "=== C. RENAME (guarded: source must exist, destination must not) ==="
ok=0
for n in pswap_armP_era5l_s100_2026_0909_2231_ep30 pswap_armP_era5l_s200_2026_0909_2232_ep30 pswap_armP_era5l_s300_2026_0909_2232_ep30; do
  src=$P/runs/$n
  dst=$P/runs/INCOMPLETE_ABORTED_$n
  if [ ! -d "$src" ]; then echo "  SKIP (source absent): $n"; continue; fi
  if [ -e "$dst" ]; then echo "  SKIP (destination exists): $dst"; continue; fi
  if [ -f "$src/test/model_epoch030/test_metrics.csv" ]; then echo "  REFUSE (has test_metrics.csv, not an aborted arm): $n"; continue; fi
  if mv "$src" "$dst"; then echo "  RENAMED: $n -> INCOMPLETE_ABORTED_$n"; ok=$((ok+1)); else echo "  FAILED: $n rc=$?"; fi
done
echo "  renamed_count=$ok (expect 3)"
echo "=== D. AFTER (expect 9 entries: 6 valid + 3 INCOMPLETE_ABORTED_*) ==="
ls -l --time-style=+%F_%T $P/runs 2>&1 | grep -v '^total' | awk '{print "  "$6"  "$7}'
echo "  valid=$(ls -d $P/runs/*_ep30 2>/dev/null | grep -vc INCOMPLETE) isolated=$(ls -d $P/runs/INCOMPLETE_* 2>/dev/null | wc -l)"
echo "=== E. LANDING DIR NUMBERS (unchanged expected: runs=9 medians=6 size=1.4G) ==="
echo "  $P : runs=$(ls $P/runs 2>/dev/null | wc -l) medians=$(ls $P/logs/*.public_median.txt 2>/dev/null | wc -l) size=$(du -sh $P 2>/dev/null | cut -f1)"
echo "=== F. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
