#!/bin/bash
# id05-adversarial seq=23: 201693 is stuck behind a02 in the GPU queue but needs no GPU.
# Cancel it, resubmit on the CPU partition, wait, and print the audit numbers.
export LC_ALL=C
A=/data1/home/$USER/adv531
IN=/data1/home/$USER/hpc_mailbox/inbox/id05-adversarial
R=$A/results/05_adversarial_robustness/id18_s100

echo "=== TIME ==="
date

echo "=== CANCEL PENDING GPU ANALYSIS ==="
ST=$(sacct -j 201693 -X -n --format=State 2>/dev/null | head -1 | tr -d ' ')
echo "201693 state=$ST"
case "$ST" in
  PENDING) scancel 201693 && echo "  cancelled 201693";;
  *) echo "  not pending, left alone";;
esac

echo "=== RESUBMIT ON CPU ==="
cp -f $IN/analyze_statistical_structure.py $A/src/adversarial/scripts/
cp -f $IN/adv531_analyze.slurm $A/
sed -i 's/\r$//' $A/src/adversarial/scripts/analyze_statistical_structure.py $A/adv531_analyze.slurm
cd $A
J=$(sbatch --parsable adv531_analyze.slurm 2>&1)
echo "job=$J"

echo "=== WAIT (max 15 min) ==="
for i in $(seq 1 90); do
  ST=$(sacct -j $J -X -n --format=State 2>/dev/null | head -1 | tr -d ' ')
  case "$ST" in
    COMPLETED|FAILED|CANCELLED*|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY) echo "state=$ST after ~${i}0s"; break;;
  esac
  sleep 10
done
sacct -j $J -X --format=JobID%14,State%14,ExitCode%8,Elapsed%10 2>&1

echo "=== STDOUT ==="
cat $A/logs/adv531_analyze_${J}.out 2>&1 | tail -60

echo "=== STDERR ==="
tail -12 $A/logs/adv531_analyze_${J}.err 2>&1

echo "=== CSV ==="
ls -l $R/statistical_structure_summary_eps0.1.csv 2>&1
