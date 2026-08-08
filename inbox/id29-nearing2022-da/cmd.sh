#!/bin/bash
# ID29 seq=11: the AR arm needs ~41.5 h but was given 36 h. Extend the wall clock in place if SLURM allows it,
# which costs nothing; only fall back to cancel+resubmit if the extension is refused.
ROOT=/data1/home/sunyiq/nearing2022_da

echo "=== A: current limit ==="
squeue -j 201859 -o "%.10i %.12j %.10T %.12M %.12l %.12L" 2>&1

echo "=== B: try to extend to 72h ==="
scontrol update jobid=201859 TimeLimit=72:00:00 2>&1
RC=$?
echo "  scontrol rc=$RC"

echo "=== C: limit after the attempt ==="
squeue -j 201859 -o "%.10i %.12j %.10T %.12M %.12l %.12L" 2>&1

echo "=== D: also extend the dependent assimilation job if needed (it is 24h, needs ~6h) ==="
squeue -j 201890 -o "%.10i %.12j %.11T %.12l %.24R" 2>&1

echo "=== E: current epoch rates, both arms ==="
for tag in sim_201858 ar_201859; do
  echo "-- $tag"
  tr '\r' '\n' < "$ROOT/logs/${tag}.out" 2>/dev/null \
    | grep -oE "Epoch [0-9]+: *[0-9]+%\|[^|]*\| *[0-9]+/[0-9]+ \[[^]]*\]" | tail -1 | sed 's/^/    /'
done

echo "=== F: simulation epochs done ==="
D=$(ls -1dt $ROOT/results/29_nearing2022_da_ar/nearing2022_simulation_seed0_*/ 2>/dev/null | head -1)
grep -cE "Epoch [0-9]+ average loss" "$D/output.log" 2>/dev/null | sed 's/^/  /'
grep -E "Epoch [0-9]+ average loss" "$D/output.log" 2>/dev/null | tail -2
