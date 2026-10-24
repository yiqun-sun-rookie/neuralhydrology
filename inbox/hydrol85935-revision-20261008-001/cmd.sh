#!/bin/bash
# USER_AUTHORIZED_NICE_REVERT 2026-10-24: set nice of 246349 and 246450 back to 0 (undo seq546/547); only where the
# current nice is still the 100000 we set; any other value is reported and left alone; touches nothing else
echo "NR_TIME $(date -u +%FT%TZ)"
echo "NR_BEFORE"; squeue -j 246349,246450 -h -o "%i|%j|%T|%Q|%y|%r" 2>&1
for J in 246349 246450; do
  N=$(squeue -j $J -h -o "%y" 2>/dev/null | sort -u | tr "\n" ","); echo "NR_NICE $J [$N]"
  case "$N" in
    "") echo "NR_SKIP $J no longer in queue";;
    "0,") echo "NR_SKIP $J already 0";;
    "100000,") scontrol update jobid=$J nice=0 2>&1; echo "NR_RC $J $?";;
    *) echo "NR_SKIP $J nice is not the value we set; left unchanged";;
  esac
done
sleep 5
echo "NR_AFTER"; squeue -j 246349,246450 -h -o "%i|%j|%T|%Q|%y|%r|%S" 2>&1
exit 0
