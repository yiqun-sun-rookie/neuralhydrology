#!/bin/bash
# READ-ONLY: close the gaps of receipt 48 found by the 2026-09-11 audit (no sbatch, no rename, no writes).
# Receipt 48 C3 said "(no BAD_era5l_precip_* found at depth 1-3)" -- that was a probe-depth artifact:
# the renamed product lives at depth 4 (data_shadow/camels_us/basin_mean_forcing/). This receipt supersedes it.
set -o pipefail
date "+wallclock %F %T %z"
P=/data1/home/sunyiq/precip_swap_daily_2026_09
F=/data1/home/sunyiq/forcing_swap_daily_2026_09
A=/data1/home/sunyiq/attr_swap_daily_2026_09
echo "=== A. MY QUEUE (header must be visible) ==="
squeue -u "$USER" -o '%.11i %.26j %.9T %.10M %.9N' 2>&1 | grep -Ei 'attrswap|fswap|pswap|JOBID'
echo "  squeue rc=${PIPESTATUS[0]}"
echo "=== A2. sacct jobs in any state after 2026-09-11 (header + rc=0 required for a valid 'none') ==="
sacct -X -S 2026-09-11 -u "$USER" --format=JobID%9,JobName%26,State%12,Submit%20,Partition%7 2>&1 | grep -Ei 'attrswap|fswap|pswap|JobID'
echo "  sacct rc=${PIPESTATUS[0]}"
echo "=== B. LANDING DIRS (same command as receipts 47/48; du does not follow symlinks) ==="
for p in $A $F $P; do
  if [ -d "$p" ]; then
    echo "  $p : runs=$(ls $p/runs 2>/dev/null | wc -l) medians=$(ls $p/logs/*.public_median.txt 2>/dev/null | wc -l) size=$(du -sh $p 2>/dev/null | cut -f1)"
  else
    echo "  MISSING: $p"
  fi
done
echo "=== C. BAD_era5l_precip_* at depth 4 (renamed by seq 39 on 2026-09-09 22:39) ==="
ls -ld --time-style=+%F_%T $P/data_shadow/camels_us/basin_mean_forcing/BAD_era5l_precip_* 2>&1 | sed 's/^/  /'
for b in $P/data_shadow/camels_us/basin_mean_forcing/BAD_era5l_precip_*; do
  [ -d "$b" ] && echo "  files in $(basename $b): $(find $b -name '*_forcing_leap.txt' 2>/dev/null | wc -l)"
done
echo "  rebuilt era5l_precip (real dir expected):"
ls -ld --time-style=+%F_%T $P/data_shadow/camels_us/basin_mean_forcing/era5l_precip 2>&1 | sed 's/^/    /'
echo "  build logs (both expected):"
ls -l --time-style=+%F_%T $P/logs/build_era5l_precip.BAD.json $P/logs/build_era5l_precip.json 2>&1 | sed 's/^/    /'
echo "=== D. SYMLINK CHAIN precip_swap -> forcing_swap -> attr_swap (targets shown) ==="
for p in $F $P; do
  echo "  --- $p/data_shadow/camels_us ---"
  ls -l --time-style=+%F_%T $p/data_shadow/camels_us 2>&1 | grep -v '^total' | sed 's/^/    /'
  echo "  --- $p/data_shadow/camels_us/basin_mean_forcing ---"
  ls -l --time-style=+%F_%T $p/data_shadow/camels_us/basin_mean_forcing 2>&1 | grep -v '^total' | sed 's/^/    /'
done
echo "  --- $A/data_shadow/camels_us (chain root) ---"
ls -l --time-style=+%F_%T $A/data_shadow/camels_us 2>&1 | grep -v '^total' | sed 's/^/    /'
echo "  --- dangling symlinks under the three data_shadow trees (find -L -type l; expect none) ---"
dang=$(find -L $A/data_shadow $F/data_shadow $P/data_shadow -type l 2>/dev/null)
if [ -n "$dang" ]; then echo "$dang" | sed 's/^/    DANGLING /'; else echo "    (none)"; fi
echo "=== E. FILE COUNTS THROUGH THE CHAIN (find -L; expect maurer 675, era5l_caravan 529, chirps 529, era5l_precip 529) ==="
for s in maurer era5l_caravan chirps era5l_precip; do
  echo "  $s $(find -L $P/data_shadow/camels_us/basin_mean_forcing/$s -name '*_forcing_leap.txt' 2>/dev/null | wc -l)"
done
echo "  forcing_swap era5l_caravan $(find -L $F/data_shadow/camels_us/basin_mean_forcing/era5l_caravan -name '*_forcing_leap.txt' 2>/dev/null | wc -l)"
echo "=== F. ARCHIVED CODE (expect camelsus.py sha256[:16] = 51e2e02b382ec103) ==="
c=$(find $A/code_1f9804e -name camelsus.py 2>/dev/null | head -1)
if [ -n "$c" ]; then echo "  $c  $(sha256sum $c | cut -c1-16)"; else echo "  MISSING camelsus.py under $A/code_1f9804e"; fi
echo "=== G. THE 3 CANCELLED ARM DIRS (still original names? no rename performed) ==="
for n in pswap_armP_era5l_s100_2026_0909_2231_ep30 pswap_armP_era5l_s200_2026_0909_2232_ep30 pswap_armP_era5l_s300_2026_0909_2232_ep30; do
  if [ -d "$P/runs/$n" ]; then echo "  ORIGINAL NAME PRESENT: $n"; else echo "  ORIGINAL NAME ABSENT : $n"; fi
done
echo "=== H. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
