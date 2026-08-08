#!/bin/bash
# ID29 seq=10: (a) find 201864, resubmit the dependency job if it is really gone,
#              (b) diagnose why the autoregression arm is ~12x slower than the simulation arm.
ROOT=/data1/home/sunyiq/nearing2022_da
RES=$ROOT/results/29_nearing2022_da_ar

echo "=== A: where is 201864 ==="
scontrol show job 201864 2>&1 | head -6
sacct -j 201864 --format=JobID%10,JobName%12,State%16,Reason%24,Submit%20 2>&1 | head -5
echo "-- all my jobs, any state --"
squeue -u "$USER" -t all -o "%.10i %.12j %.11T %.24R" 2>&1

echo "=== B: submit arm 3 with a dependency, unless one already exists ==="
HAVE=$(squeue -u "$USER" -h -o "%j" 2>/dev/null | grep -c "id29_da")
if [ "$HAVE" -gt 0 ]; then
  echo "  already queued ($HAVE), not submitting again"
else
  DA=$(sbatch --parsable --dependency=afterok:201858 inbox/id29_assimilation.slurm 2>&1)
  echo "  da_jobid=$DA"
  sleep 5
  squeue -u "$USER" -o "%.10i %.12j %.11T %.24R" 2>&1
fi

echo "=== C: autoregression speed - has epoch 1 finished yet ==="
D=$(ls -1dt $RES/nearing2022_autoregression_*/ 2>/dev/null | head -1)
grep -cE "Epoch [0-9]+ average loss" "$D/output.log" 2>/dev/null | sed 's/^/  completed epochs: /'
echo "  last tqdm state:"
tr '\r' '\n' < "$ROOT/logs/ar_201859.out" 2>/dev/null | grep -oE "Epoch [0-9]+: *[0-9]+%\|[^|]*\| *[0-9]+/[0-9]+ \[[^]]*\]" | tail -2 | sed 's/^/    /'
echo "  simulation for comparison:"
tr '\r' '\n' < "$ROOT/logs/sim_201858.out" 2>/dev/null | grep -oE "Epoch [0-9]+: *[0-9]+%\|[^|]*\| *[0-9]+/[0-9]+ \[[^]]*\]" | tail -2 | sed 's/^/    /'

echo "=== D: is the AR job actually on GPU or has it fallen back to CPU ==="
grep -iE "device|cuda|gpu:" "$ROOT/logs/ar_201859.out" 2>/dev/null | head -4
D2=$(ls -1dt $RES/nearing2022_autoregression_*/ 2>/dev/null | head -1)
grep -iE "device|GPU" "$D2/output.log" 2>/dev/null | head -4

echo "=== E: node load (via slurm, not ssh) ==="
scontrol show node ngu104 2>&1 | tr ' ' '\n' | grep -E "^CPUAlloc|^CPUTot|^AllocTRES|^State" | head -6
squeue -w ngu104 -o "%.10i %.10u %.12j %.10T %.20b" 2>&1 | head -8
