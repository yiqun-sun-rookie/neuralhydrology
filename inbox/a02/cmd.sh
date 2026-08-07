#!/bin/bash
# a02 seq=7 : submit the smoke job (4 gates) and wait for it.
# Gates: env+CUDA / full sha256 package verification / 1-epoch training /
#        config contract diff against the A01R1 baseline.
export LC_ALL=C
PKG=/data1/home/$USER/nature_1st_a02
cd $PKG/hpc || exit 1

echo "=== SUBMIT ==="
JID=$(sbatch --parsable a02_smoke.slurm 2>&1)
echo "  jobid=$JID"
echo "$JID" > $PKG/.smoke_jobid

echo "=== WAIT (max 55 min) ==="
for i in $(seq 1 330); do
  ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
  [ -z "$ST" ] && { echo "  finished at t=$((i*10))s"; break; }
  [ $((i % 12)) -eq 0 ] && echo "  t=$((i*10))s state=$ST node=$(squeue -j "$JID" -h -o '%R' 2>/dev/null)"
  sleep 10
done

echo "=== ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%10,JobName%12,NodeList%10,State%12,ExitCode%8,Elapsed%10 2>&1

echo "=== STDOUT (tail 60) ==="
tail -60 $PKG/logs/a02_smoke-${JID}.out 2>&1

echo "=== STDERR (tail 15) ==="
tail -15 $PKG/logs/a02_smoke-${JID}.err 2>&1
