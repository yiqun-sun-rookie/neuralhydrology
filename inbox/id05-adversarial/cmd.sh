#!/bin/bash
# id05-adversarial seq=1
# Deploy payload v2 (all runners chunkable + the new random-window control),
# gate on a one-basin smoke of the new code, then launch the full 531 campaign.
set -o pipefail
export LC_ALL=C
DST=/data1/home/$USER/adv531
MB=/data1/home/$USER/hpc_mailbox
IN=$MB/inbox/id05-adversarial

echo "=== 1. DEPLOY PAYLOAD v2 ==="
echo "  md5=$(md5sum $MB/payload/adv531_v2.tar.gz | cut -c1-32)  expect=a122366e74b6677ecd1630d54cd08153"
tar xzf $MB/payload/adv531_v2.tar.gz -C $DST || { echo "UNPACK_FAILED"; exit 1; }
find $DST/src -name "*.py" -exec sed -i 's/\r$//' {} \;
cp -f $IN/adv531_block.slurm $IN/adv531_smoke2.slurm $DST/
sed -i 's/\r$//' $DST/adv531_block.slurm $DST/adv531_smoke2.slurm
mkdir -p $DST/logs $DST/results/05_adversarial_robustness/id18_s100_hpc

P=/data1/home/$USER/miniconda3/envs/nh_final/bin/python
echo "  new options present:"
for s in run_exp2 run_exp3 run_exp4 run_exp5 run_exp6 run_exp_detect run_ksweep; do
  printf "    %-16s " "$s"
  $P $DST/src/adversarial/scripts/$s.py --help 2>&1 | tr '\n' ' ' | grep -o -- "--offset" | head -1
  echo ""
done
printf "    run_exp4 control: "; $P $DST/src/adversarial/scripts/run_exp4.py --help 2>&1 | grep -c -- "--random-control"
printf "    l1l2 offset:      "; $P $DST/src/adversarial/scripts/run_exp_l1l2.py --help 2>&1 | grep -c -- "--offset"

echo "=== 2. GATE: smoke the new random-window control (1 basin) ==="
cd $DST
SJ=$(sbatch --parsable adv531_smoke2.slurm 2>&1)
echo "  smoke jobid=$SJ"
for i in $(seq 1 90); do
  ST=$(squeue -j "$SJ" -h -o "%t" 2>/dev/null)
  [ -z "$ST" ] && break
  [ $((i % 6)) -eq 0 ] && echo "  t=$((i*10))s state=$ST"
  sleep 10
done
sacct -j "$SJ" -X --format=JobID%10,State%12,ExitCode%8,Elapsed%10 2>&1
echo "--- smoke log ---"
cat $DST/logs/smoke2_${SJ}.out 2>/dev/null | tail -25

if ! grep -q "EXPOSURE-MATCH AND SIGN CHECK: PASS" $DST/logs/smoke2_${SJ}.out 2>/dev/null; then
  echo "=== GATE FAILED -> NOT LAUNCHING THE CAMPAIGN ==="
  cat $DST/logs/smoke2_${SJ}.err 2>/dev/null | tail -15
  exit 0
fi
echo "=== GATE PASSED ==="

echo "=== 3. LAUNCH FULL 531 CAMPAIGN (8 blocks x 5 chunks = 40 array tasks) ==="
for b in exp2 l1l2 exp3 exp6 detect exp5 exp4 ksweep; do
  J=$(sbatch --parsable -J adv531_$b $DST/adv531_block.slurm $b 2>&1)
  echo "  $b -> $J"
done

echo "=== 4. QUEUE STATE ==="
squeue -u $USER -o "%.12i %.14j %.3t %.10M %.6D %R" 2>&1 | head -25
echo "  total tasks queued: $(squeue -u $USER -h -r 2>/dev/null | wc -l)"
