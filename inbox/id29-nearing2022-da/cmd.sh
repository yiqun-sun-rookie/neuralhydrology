#!/bin/bash
# ID29 seq=12: the AR arm needs ~38 h but has a 36 h limit and SLURM refuses to extend a running job.
# Only 1 epoch is in flight (none completed), so cancel and resubmit with a 72 h limit - nothing is lost.
# The simulation arm (201858) and the dependent assimilation job (201890) are NOT touched.
cd ~/hpc_mailbox || exit 1
ROOT=/data1/home/sunyiq/nearing2022_da

echo "=== A: confirm nothing completed yet on the AR arm ==="
D=$(ls -1dt $ROOT/results/29_nearing2022_da_ar/nearing2022_autoregression_*/ 2>/dev/null | head -1)
echo "  run=$D"
echo "  completed epochs: $(grep -cE 'Epoch [0-9]+ average loss' "$D/output.log" 2>/dev/null)"
echo "  checkpoints: $(ls "$D" 2>/dev/null | grep -c model_epoch)"

echo "=== B: cancel the AR arm only ==="
scancel 201859 2>&1
sleep 10
squeue -u "$USER" -o "%.10i %.12j %.11T %.12l %.20R" 2>&1

echo "=== C: resubmit with 72 h ==="
AR=$(sbatch --parsable inbox/id29_autoregression.slurm 2>&1)
echo "  new ar_jobid=$AR"
sleep 30
squeue -u "$USER" -o "%.10i %.12j %.11T %.12M %.12l %.20R" 2>&1

echo "=== D: sanity - the simulation arm and the dependency job must be untouched ==="
sacct -j 201858,201890 -X --format=JobID%10,JobName%12,State%14,Elapsed%10,Timelimit%12 2>&1 | head -6

echo "=== E: simulation progress ==="
S=$(ls -1dt $ROOT/results/29_nearing2022_da_ar/nearing2022_simulation_seed0_*/ 2>/dev/null | head -1)
echo "  epochs done: $(grep -cE 'Epoch [0-9]+ average loss' "$S/output.log" 2>/dev/null) / 30"
grep -E "Epoch [0-9]+ average loss" "$S/output.log" 2>/dev/null | tail -1
