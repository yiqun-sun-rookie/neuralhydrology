#!/bin/bash
# id05-adversarial seq=22: collect moment-audit array 201637 and dependent analysis 201693.
export LC_ALL=C
A=/data1/home/$USER/adv531
R=$A/results/05_adversarial_robustness/id18_s100
REC=$R/statistical_constraint_records_eps0.1

echo "=== TIME ==="
date

echo "=== JOBS ==="
sacct -j 201637,201693 -X --format=JobID%14,JobName%16,State%14,ExitCode%8,Elapsed%10 2>&1

echo "=== RECORDS ==="
ls -1 $REC/*.npz 2>/dev/null | wc -l

echo "=== MOMENT CHUNK TAILS ==="
for i in 0 1 2 3 4; do
  echo "--- chunk $i ---"
  tail -2 $A/logs/adv531_moment_201637_${i}.out 2>&1
done
echo "--- moment err bytes ---"
ls -l $A/logs/adv531_moment_201637_*.err 2>&1 | awk '{print $5, $9}'

echo "=== ANALYSIS STDOUT ==="
cat $A/logs/adv531_analyze_201693.out 2>&1 | tail -60

echo "=== ANALYSIS STDERR ==="
tail -12 $A/logs/adv531_analyze_201693.err 2>&1

echo "=== SUMMARY CSV ==="
ls -l $R/statistical_structure_summary_eps0.1.csv 2>&1

echo "=== QUEUE ==="
squeue -u $USER -o "%.16i %.16j %.3t %.10M %.24R" 2>&1 | head -8
