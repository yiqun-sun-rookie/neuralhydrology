#!/bin/bash
# id05-adversarial seq=27: re-run l2-signature + drought analyses on all 531 basins.
export LC_ALL=C
A=/data1/home/$USER/adv531
IN=/data1/home/$USER/hpc_mailbox/inbox/id05-adversarial
R=$A/results/05_adversarial_robustness/id18_s100

echo "=== TIME ==="
date

echo "=== PRECONDITIONS ==="
echo "l1l2_records npz: $(ls -1 $R/l1l2_records/*.npz 2>/dev/null | wc -l)"
echo "camels data dir : $(ls -d $A/data/camels_us 2>&1)"
ls -1 $A/data/camels_us 2>/dev/null | head -4

echo "=== BACKUP EXISTING L2 SUMMARY ==="
cp -p $R/l2_signatures_summary.csv $R/l2_signatures_summary.csv.bak_seq27 2>&1 && echo "  backed up"

echo "=== SUBMIT ==="
cp -f $IN/adv531_l2drought.slurm $A/
sed -i 's/\r$//' $A/adv531_l2drought.slurm
cd $A
J=$(sbatch --parsable adv531_l2drought.slurm 2>&1)
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
cat $A/logs/adv531_l2drought_${J}.out 2>&1 | tail -70

echo "=== STDERR ==="
tail -10 $A/logs/adv531_l2drought_${J}.err 2>&1

echo "=== ROW COUNTS AFTER ==="
for f in l2_signatures_summary.csv drought_mechanism_summary.csv; do
  printf "  %-34s %s rows\n" "$f" "$(($(wc -l < $R/$f 2>/dev/null || echo 1) - 1))"
done
