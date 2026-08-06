#!/bin/bash
# seq=15  ship the corrected run_exp2.py (the packaged copy predated --limit) and rerun the smoke test.
set -o pipefail
export LC_ALL=C
DST=/data1/home/$USER/adv531
MB=/data1/home/$USER/hpc_mailbox

echo "=== 1. REPLACE run_exp2.py ==="
cp -f $MB/inbox/run_exp2.py $DST/src/adversarial/scripts/run_exp2.py
sed -i 's/\r$//' $DST/src/adversarial/scripts/run_exp2.py
echo "  md5=$(md5sum $DST/src/adversarial/scripts/run_exp2.py | cut -c1-32)  expect=0cfe789646efbc85c9d6526ba1c598c3"
grep -c "add_argument" $DST/src/adversarial/scripts/run_exp2.py | sed 's/^/  argparse options: /'
/data1/home/$USER/miniconda3/envs/nh_final/bin/python $DST/src/adversarial/scripts/run_exp2.py --help 2>&1 | head -4 | sed 's/^/  /'

echo "=== 2. SUBMIT SMOKE ==="
cd $DST
JID=$(sbatch --parsable adv531_smoke.slurm 2>&1)
echo "  jobid=$JID"

echo "=== 3. WAIT (max 15 min) ==="
for i in $(seq 1 90); do
  ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
  [ -z "$ST" ] && break
  [ $((i % 6)) -eq 0 ] && echo "  t=$((i*10))s state=$ST"
  sleep 10
done

echo "=== 4. RESULT ==="
sacct -j "$JID" -X --format=JobID%10,JobName%14,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1
echo "--- stdout ---"
cat $MB/outbox/slurm_${JID}.out 2>/dev/null | tail -40
echo "--- stderr (tail) ---"
cat $MB/outbox/slurm_${JID}.err 2>/dev/null | tail -8
rm -f $MB/outbox/slurm_*.out $MB/outbox/slurm_*.err
