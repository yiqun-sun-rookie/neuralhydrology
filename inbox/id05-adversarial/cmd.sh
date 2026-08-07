#!/bin/bash
# id05-adversarial seq=19: liveness + state report + IDEMPOTENT re-issue of the 531-basin moment audit.
# Submits adv531_moment.slurm only if sacct shows no such job today.
export LC_ALL=C
A=/data1/home/$USER/adv531
IN=/data1/home/$USER/hpc_mailbox/inbox/id05-adversarial
P=/data1/home/$USER/miniconda3/envs/nh_final/bin/python

echo "=== HOST/TIME ==="
hostname; date

echo "=== DID SEQ18 LAND ==="
ls -l $A/adv531_moment.slurm 2>&1
md5sum $A/src/adversarial/scripts/run_statistical_structure_probe.py 2>&1 | cut -c1-33
echo "  expect probe md5=b45d49568d9b06f49e295a3e0b6625b1"

echo "=== QUEUE NOW ==="
squeue -u $USER -o "%.14i %.18j %.3t %.10M %.20R" 2>&1 | head -12

echo "=== JOBS TODAY ==="
sacct -S 2026-08-07 -X --format=JobID%14,JobName%16,State%12,ExitCode%8,Elapsed%10 2>&1 | head -25

echo "=== IDEMPOTENT SUBMIT ==="
NJ=$(sacct -S 2026-08-07 -X -n --format=JobName%20 2>/dev/null | grep -c adv531_moment)
echo "existing adv531_moment records today: ${NJ:-0}"
if [ "${NJ:-0}" -eq 0 ]; then
  cp -f $IN/run_statistical_structure_probe.py $A/src/adversarial/scripts/
  cp -f $IN/adv531_moment.slurm $A/
  sed -i 's/\r$//' $A/src/adversarial/scripts/run_statistical_structure_probe.py $A/adv531_moment.slurm
  mkdir -p $A/logs
  echo "  probe md5 after copy=$(md5sum $A/src/adversarial/scripts/run_statistical_structure_probe.py | cut -c1-32)"
  $P $A/src/adversarial/scripts/run_statistical_structure_probe.py --help 2>&1 | grep -c offset | sed 's/^/  offset option present: /'
  cd $A
  J=$(sbatch --parsable adv531_moment.slurm 2>&1)
  echo "  submitted: $J"
else
  echo "  already submitted earlier, skipping sbatch"
fi

echo "=== QUEUE AFTER ==="
squeue -u $USER -o "%.14i %.18j %.3t %.10M" 2>&1 | head -12
