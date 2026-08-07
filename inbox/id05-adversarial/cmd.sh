#!/bin/bash
# id05-adversarial seq=28: full l2 stdout (head) + ship l2/drought summaries back.
export LC_ALL=C
A=/data1/home/$USER/adv531
R=$A/results/05_adversarial_robustness/id18_s100
M=/data1/home/$USER/hpc_mailbox

echo "=== TIME ==="
date

echo "=== L2 STDOUT (head, the part truncated last time) ==="
sed -n '1,40p' $A/logs/adv531_l2drought_201712.out 2>&1

cd $M || exit 1
mkdir -p outbox/id05-adversarial/data
cp -f $R/l2_signatures_summary.csv outbox/id05-adversarial/data/
cp -f $R/drought_mechanism_summary.csv outbox/id05-adversarial/data/

echo "=== SHIPPED ==="
for f in l2_signatures_summary.csv drought_mechanism_summary.csv; do
  echo "$(md5sum outbox/id05-adversarial/data/$f | cut -d' ' -f1)  $f  $(($(wc -l < outbox/id05-adversarial/data/$f) - 1)) rows"
done

echo "=== EXACT-MOMENT PROGRESS ==="
sacct -j 201707 -X --format=JobID%14,State%12,Elapsed%10 2>&1 | head -8
for i in 0 1 2 3 4; do
  echo -n "  chunk $i: "; tail -2 $A/logs/adv531_exact_201707_${i}.out 2>/dev/null | head -1
done
