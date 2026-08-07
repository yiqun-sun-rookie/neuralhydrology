#!/bin/bash
# id05-adversarial seq=21: queue the structure analysis as a dependent job so it fires the
# moment the 201637 array finishes. Returns immediately; does not hog the serial runner.
export LC_ALL=C
A=/data1/home/$USER/adv531
IN=/data1/home/$USER/hpc_mailbox/inbox/id05-adversarial
REC=$A/results/05_adversarial_robustness/id18_s100/statistical_constraint_records_eps0.1

echo "=== TIME ==="
date

echo "=== ARRAY 201637 ==="
sacct -j 201637 -X --format=JobID%14,State%12,ExitCode%8,Elapsed%10 2>&1

echo "=== RECORDS SO FAR ==="
ls -1 $REC/*.npz 2>/dev/null | wc -l

echo "=== DEPENDENT ANALYSIS ==="
NA=$(sacct -S 2026-08-07 -X -n --format=JobName%20 2>/dev/null | grep -c adv531_analyze)
echo "existing adv531_analyze records today: ${NA:-0}"
if [ "${NA:-0}" -eq 0 ]; then
  cp -f $IN/analyze_statistical_structure.py $A/src/adversarial/scripts/
  cp -f $IN/adv531_analyze.slurm $A/
  sed -i 's/\r$//' $A/src/adversarial/scripts/analyze_statistical_structure.py $A/adv531_analyze.slurm
  mkdir -p $A/logs
  cd $A
  J=$(sbatch --parsable --dependency=afterok:201637 adv531_analyze.slurm 2>&1)
  echo "  queued: $J (starts after 201637 completes)"
else
  echo "  already queued/run, skipping"
fi

echo "=== QUEUE ==="
squeue -u $USER -o "%.16i %.16j %.3t %.10M %.26R" 2>&1 | head -12
