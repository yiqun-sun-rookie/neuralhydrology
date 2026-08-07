#!/bin/bash
# id05-adversarial seq=29: exact-moment counterfactual progress.
export LC_ALL=C
A=/data1/home/$USER/adv531
echo "=== TIME ==="; date
echo "=== JOB 201707 ==="
sacct -j 201707 -X --format=JobID%14,State%12,ExitCode%8,Elapsed%10 2>&1 | head -8
echo "=== CHUNK PROGRESS ==="
for i in 0 1 2 3 4; do
  echo -n "  chunk $i: "; grep -E "^\[[0-9]+/" $A/logs/adv531_exact_201707_${i}.out 2>/dev/null | tail -1
done
echo "=== PARTS WRITTEN ==="
ls -l $A/results/05_adversarial_robustness/id18_s100/exact_moment_probe_eps0.1_part*.csv 2>&1 | awk '{print "  ", $5, $9}'
