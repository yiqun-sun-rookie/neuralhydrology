#!/usr/bin/env bash
# ID33 seq=3 : read-only status of the six arms. No sbatch, no writes.
set -o pipefail
echo "=== STAMP ==="; date -Is
echo "=== SACCT ==="
sacct -j 220490,220491,220492,220493,220494,220495 -X \
  --format=JobID%9,JobName%10,State%12,ExitCode%8,Elapsed%11,Start%20,NodeList%9 2>&1 || true
echo "=== QUEUE REASON ==="
squeue -j 220490,220491,220492,220493,220494,220495 -o "%.9i %.10j %.2t %.11M %.30R %.20S" 2>&1 || true
echo "=== ANY EPOCH LOGGED YET ==="
R=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo/results/33_transformer_recipe_repair
for a in T1 T2 T3 T4 T5 L33; do
  f=$(find "$R/$a" -name output.log -type f 2>/dev/null | head -1)
  if test -n "$f"; then
    n=$(grep -c 'average validation loss' "$f" 2>/dev/null || echo 0)
    last=$(grep 'Median validation metrics' "$f" 2>/dev/null | tail -1 | sed 's/.*NSE: //')
    echo "  $a: epochs_validated=$n  last_NSE=${last:-none}"
  else echo "  $a: no output.log yet"; fi
done
echo ID33_STATUS_SEQ3_COMPLETE
