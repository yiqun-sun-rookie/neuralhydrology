#!/usr/bin/env bash
# ID33 seq=5 : widen ONLY job 220495 (L33) to hgpu2p+hgpu2. Same RTX 3090 card type, so the
# frozen bit-reproducibility contract (card type + capability + library versions) is unchanged.
# No cancel, no resubmit, no new machine time. Nothing else is touched.
set -o pipefail
echo "=== STAMP ==="; date -Is

echo "=== A. BEFORE ==="
squeue -j 220495 -o "%.9i %.10j %.14P %.2t %.22R %.20S" 2>&1 || true
echo "-- confirm it is still PENDING before touching it --"
ST=$(squeue -j 220495 -h -o "%t" 2>/dev/null)
echo "state=$ST"
if [ "$ST" != "PD" ]; then echo "NOT_PENDING_ABORT"; exit 0; fi

echo "=== B. hgpu2 CAPACITY AND CARD TYPE CHECK ==="
sinfo -p hgpu2 -o "%.10P %.8D %.8t %.20N" 2>&1 || true

echo "=== C. WIDEN PARTITION LIST (220495 ONLY) ==="
scontrol update jobid=220495 partition=hgpu2p,hgpu2 2>&1 && echo "UPDATE_ISSUED" || echo "UPDATE_FAILED"

echo "=== D. AFTER ==="
squeue -j 220495 -o "%.9i %.10j %.14P %.2t %.22R %.20S" 2>&1 || true

echo "=== E. NOTHING ELSE MOVED ==="
squeue -u "$USER" -o "%.9i %.12j %.14P %.2t %.11M %.20R" 2>&1 | grep -E 'JOBID|id33' || true

echo "=== F. DEAD JOBS SITTING IN THE QUEUE (report only, do not touch) ==="
squeue -u "$USER" -h -o "%.9i %.14j %.30R" 2>&1 | grep -i 'DependencyNeverSat\|JobHeldUser' || echo "  none"

echo "=== G. ID33 PROGRESS ==="
R=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo/results/33_transformer_recipe_repair
for a in T1 T2 T3 T4 T5; do
  f=$(find "$R/$a" -name output.log -type f 2>/dev/null | head -1)
  if test -n "$f"; then
    last=$(grep 'Median validation metrics' "$f" 2>/dev/null | tail -1 | sed 's/.*NSE: //')
    n=$(grep -c 'average validation loss' "$f" 2>/dev/null || true)
    echo "  $a: epochs_validated=${n:-0} last_NSE=${last:-none}"
  else echo "  $a: no log yet"; fi
done
echo ID33_PARTITION_SEQ5_COMPLETE
