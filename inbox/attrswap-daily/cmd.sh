#!/bin/bash
# READ-ONLY: new-session first check against HANDOFF_20260911 (no sbatch, no rename, no writes).
set -o pipefail
date "+wallclock %F %T %z"
echo "=== A. MY QUEUE (any attrswap/fswap/pswap job queued or running?) ==="
squeue -u "$USER" -o '%.11i %.26j %.9T %.10M %.9N' 2>&1 | grep -Ei 'attrswap|fswap|pswap|JOBID' || echo '  (none of this campaign queued or running)'
echo "=== A2. ANY CAMPAIGN JOB SUBMITTED SINCE 2026-09-11 (expect none) ==="
sacct -X -S 2026-09-11 -u "$USER" --format=JobID%9,JobName%26,State%12,Submit%20,Partition%7 2>&1 | grep -Ei 'attrswap|fswap|pswap' || echo '  (no campaign job submitted since 2026-09-11)'
echo "=== B. LANDING DIRS (handoff: 7/7 522M, 9/9 1.2G, 9/6 1.4G) ==="
for d in attr_swap_daily_2026_09 forcing_swap_daily_2026_09 precip_swap_daily_2026_09; do
  p=/data1/home/sunyiq/$d
  if [ -d "$p" ]; then
    echo "  $p : runs=$(ls $p/runs 2>/dev/null | wc -l) medians=$(ls $p/logs/*.public_median.txt 2>/dev/null | wc -l) size=$(du -sh $p 2>/dev/null | cut -f1)"
  else
    echo "  MISSING: $p"
  fi
done
ls -d /data1/home/sunyiq/*_2026_09.* 2>/dev/null | sed 's/^/  old copy: /'
echo "=== C. precip_swap runs/ listing with mtime (9 entries expected) ==="
ls -l --time-style=+%F_%T /data1/home/sunyiq/precip_swap_daily_2026_09/runs 2>&1 | grep -v '^total' | awk '{print "  "$6"  "$7}'
echo "=== C2. THE 3 CANCELLED ARM DIRS: STILL UNDER ORIGINAL NAMES? ==="
for n in pswap_armP_era5l_s100_2026_0909_2231_ep30 pswap_armP_era5l_s200_2026_0909_2232_ep30 pswap_armP_era5l_s300_2026_0909_2232_ep30; do
  q=/data1/home/sunyiq/precip_swap_daily_2026_09/runs/$n
  if [ -d "$q" ]; then
    if [ -f "$q/test/model_epoch030/test_metrics.csv" ]; then tm=yes; else tm=no; fi
    echo "  ORIGINAL NAME PRESENT: $n  (test_metrics.csv present: $tm)"
  else
    echo "  ORIGINAL NAME ABSENT : $n"
  fi
done
iso=$(ls -d /data1/home/sunyiq/precip_swap_daily_2026_09/runs/INCOMPLETE_* 2>/dev/null)
if [ -n "$iso" ]; then echo "$iso" | sed 's/^/  isolated on hpc: /'; else echo '  (no INCOMPLETE_* dir on hpc)'; fi
echo "=== C3. renamed BAD_era5l_precip_* products (find maxdepth 3) ==="
bad=$(find /data1/home/sunyiq/precip_swap_daily_2026_09 -maxdepth 3 -name 'BAD_era5l_precip*' 2>/dev/null)
if [ -n "$bad" ]; then echo "$bad" | sed 's/^/  /'; else echo '  (no BAD_era5l_precip_* found at depth 1-3)'; fi
echo "=== D. test_metrics.csv row counts, 6 valid precip_swap runs (expect 530 each) ==="
for q in /data1/home/sunyiq/precip_swap_daily_2026_09/runs/pswap_armP_chirps_s*_2026_0909_2231_ep30 /data1/home/sunyiq/precip_swap_daily_2026_09/runs/pswap_armP_era5l_s*_2026_0909_224*_ep30; do
  f=$q/test/model_epoch030/test_metrics.csv
  if [ -f "$f" ]; then echo "  $(wc -l < $f)  $(basename $q)"; else echo "  MISSING  $(basename $q)"; fi
done
echo "=== E. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
