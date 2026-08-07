#!/bin/bash
# id05-adversarial seq=20: check moment-audit array 201637, then run the structure analysis via sbatch.
export LC_ALL=C
A=/data1/home/$USER/adv531
IN=/data1/home/$USER/hpc_mailbox/inbox/id05-adversarial
R=$A/results/05_adversarial_robustness/id18_s100
REC=$R/statistical_constraint_records_eps0.1

echo "=== TIME ==="
date

echo "=== MOMENT ARRAY 201637 ==="
sacct -j 201637 -X --format=JobID%14,JobName%16,State%12,ExitCode%8,Elapsed%10 2>&1

echo "=== CHUNK LOG TAILS ==="
for i in 0 1 2 3 4; do
  echo "--- chunk $i ---"
  tail -3 $A/logs/adv531_moment_201637_${i}.out 2>&1
done

echo "=== ERR SIZES ==="
ls -l $A/logs/adv531_moment_201637_*.err 2>&1 | awk '{print $5, $9}'
grep -h -i -E "Traceback|CUDA_ERROR|out of memory" $A/logs/adv531_moment_201637_*.err 2>/dev/null | head -5
echo "(err grep end)"

echo "=== RECORDS ==="
N=$(ls -1 $REC/*.npz 2>/dev/null | wc -l)
echo "npz count: $N"
du -sh $REC 2>&1

echo "=== ANALYSIS ==="
if [ "${N:-0}" -ge 500 ]; then
  cp -f $IN/analyze_statistical_structure.py $A/src/adversarial/scripts/
  cp -f $IN/adv531_analyze.slurm $A/
  sed -i 's/\r$//' $A/src/adversarial/scripts/analyze_statistical_structure.py $A/adv531_analyze.slurm
  cd $A
  J=$(sbatch --parsable adv531_analyze.slurm 2>&1)
  echo "analysis job: $J"
  for i in $(seq 1 80); do
    ST=$(sacct -j $J -X -n --format=State 2>/dev/null | head -1 | tr -d ' ')
    case "$ST" in
      COMPLETED|FAILED|CANCELLED*|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY) echo "state=$ST after ${i}0s"; break;;
    esac
    sleep 10
  done
  sacct -j $J -X --format=JobID%14,State%12,ExitCode%8,Elapsed%10 2>&1
  echo "--- stdout ---"
  cat $A/logs/adv531_analyze_${J}.out 2>&1 | tail -60
  echo "--- stderr tail ---"
  tail -15 $A/logs/adv531_analyze_${J}.err 2>&1
  echo "--- summary csv ---"
  ls -l $R/statistical_structure_summary_eps0.1.csv 2>&1
else
  echo "only $N records, expected 531 -- analysis NOT submitted"
fi
