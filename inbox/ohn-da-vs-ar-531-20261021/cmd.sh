#!/bin/bash
# Own pending A1+DA 246280 / P3 246281: every 3090 except ngu002 is busy, start estimate 10-25 23:38. ngu002 (same 3090
# type) is idle; its GPU0 ran 3.4x slow on 10-22 but GPU1 / short tests were fine. Lift the exclusion for these two
# pending jobs only; the hourly speed rule (>40 s/basin) catches a slow GPU, and that task is then requeued elsewhere.
set -o pipefail
date --iso-8601=seconds
for J in 246280 246281; do
  st=$(squeue -j $J -h -o '%T' 2>/dev/null | sort -u | tr '\n' ' ')
  echo "job $J states: ${st:-GONE}"
  case "$st" in *PENDING*) scontrol update jobid=$J ExcNodeList= 2>&1 && echo "  -> ExcNodeList cleared" ;; esac
done
sleep 60
squeue -j 246280,246281 -h -o '%i|%T|%R|%N|%S' 2>&1 | head -6
for J in 246280 246281; do scontrol show job $J 2>/dev/null | grep -oE 'ExcNodeList=[^ ]*' | sort -u | head -1; done
echo "SEQ71_DONE"
