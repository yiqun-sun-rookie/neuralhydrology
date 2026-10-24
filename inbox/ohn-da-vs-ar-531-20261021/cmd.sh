#!/bin/bash
# OWN pending A1+DA tasks 246280_4 and 246911_0: a full DA run takes 3:03-3:11 on a healthy 3090 (10 completed so far).
# Lower their limit from 6:00 to 4:30 (~40% margin) so backfill can place them sooner. Limits only go down. Nothing else.
set -o pipefail
date --iso-8601=seconds
for J in 246280_4 246911_0; do
  st=$(squeue -j $J -h -o '%T' 2>/dev/null | head -1)
  echo "$J state=${st:-GONE}"
  [ "$st" = PENDING ] && scontrol update jobid=$J TimeLimit=4:30:00 2>&1 && echo "  -> TimeLimit=4:30:00"
done
sleep 60
squeue -j 246280,246911,246281 -h --start -o '%i|%T|%R|%l|%S|%N' 2>&1 | head -8
echo "SEQ78_DONE"
