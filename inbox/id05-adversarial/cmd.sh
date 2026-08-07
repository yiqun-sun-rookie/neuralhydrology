#!/bin/bash
# id05-adversarial seq=25: launch the exact-moment counterfactual on all 531 recorded basins.
export LC_ALL=C
A=/data1/home/$USER/adv531
IN=/data1/home/$USER/hpc_mailbox/inbox/id05-adversarial
REC=$A/results/05_adversarial_robustness/id18_s100/statistical_constraint_records_eps0.1

echo "=== TIME ==="
date

echo "=== PRECONDITIONS ==="
echo "npz records: $(ls -1 $REC/*.npz 2>/dev/null | wc -l)  (need 531)"
ls -l $A/results/05_adversarial_robustness/id18_s100/exp2_constraint_ablation.json 2>&1

echo "=== IDEMPOTENT SUBMIT ==="
NE=$(sacct -S 2026-08-07 -X -n --format=JobName%20 2>/dev/null | grep -c adv531_exact)
echo "existing adv531_exact records today: ${NE:-0}"
if [ "${NE:-0}" -eq 0 ]; then
  cp -f $IN/run_exact_moment_probe.py $A/src/adversarial/scripts/
  cp -f $IN/adv531_exact.slurm $A/
  sed -i 's/\r$//' $A/src/adversarial/scripts/run_exact_moment_probe.py $A/adv531_exact.slurm
  mkdir -p $A/logs
  echo "  probe md5=$(md5sum $A/src/adversarial/scripts/run_exact_moment_probe.py | cut -c1-32)"
  echo "  expect  =d936884bc788fae2606903f5498eb71b"
  cd $A
  J=$(sbatch --parsable adv531_exact.slurm 2>&1)
  echo "  submitted: $J"
else
  echo "  already submitted, skipping"
fi

echo "=== QUEUE ==="
squeue -u $USER -o "%.16i %.16j %.3t %.10M %.22R" 2>&1 | head -10
