#!/bin/bash
# Stage-2 tables batch 1 of 2: install the shipped Earth Engine tables into the own landing dir and verify hashes.
# No sbatch. No backslash literals anywhere in this file.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap2_daily_2026_09
PL=$HOME/hpc_mailbox/inbox/attrswap-daily/payload/pswap2/tables
echo "=== A. install tables (batch 1) ==="
for p in imerg_refday imerg_uncal_refday imerg_utc; do
  f=$PL/${p}_daily_529.csv.gz
  [ -f "$f" ] || { echo "MISSING $f"; exit 1; }
  cp "$f" $R/hpc_deploy/
  echo "  $(sha256sum $R/hpc_deploy/${p}_daily_529.csv.gz | cut -c1-16) $(stat -c %s $R/hpc_deploy/${p}_daily_529.csv.gz) ${p}_daily_529.csv.gz"
done
echo "=== B. tables now in landing dir ==="
ls -la $R/hpc_deploy/*.csv.gz | sed 's/^/  /'
echo "=== C. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
