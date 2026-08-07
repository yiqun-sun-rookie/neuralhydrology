#!/bin/bash
# id05-adversarial seq=32: ship the five exact-moment part CSVs back; merge locally.
export LC_ALL=C
A=/data1/home/$USER/adv531
R=$A/results/05_adversarial_robustness/id18_s100
M=/data1/home/$USER/hpc_mailbox

echo "=== TIME ==="; date
cd $M || exit 1
mkdir -p outbox/id05-adversarial/data
cp -f $R/exact_moment_probe_eps0.1_part*.csv outbox/id05-adversarial/data/
echo "=== SHIPPED ==="
for f in outbox/id05-adversarial/data/exact_moment_probe_eps0.1_part*.csv; do
  echo "  $(md5sum $f | cut -d' ' -f1)  $(basename $f)  $(($(wc -l < $f) - 1)) rows"
done
echo "=== ERR CHECK ==="
ls -l $A/logs/adv531_exact_201707_*.err 2>&1 | awk '{print "  ", $5, $9}'
grep -h -i -E "Traceback|CUDA_ERROR|out of memory" $A/logs/adv531_exact_201707_*.err 2>/dev/null | head -3
echo "  (err grep end)"
