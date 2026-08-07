#!/bin/bash
# a02 seq=9 : submit the 12 production jobs (user-authorised 2026-08-07 after smoke green).
# 6 shared seeds (42-47) x 2 arms (preceding | same_time), paired arms adjacent.
export LC_ALL=C
PKG=/data1/home/$USER/nature_1st_a02
cd $PKG/hpc || exit 1

echo "=== A PRE-SUBMIT SANITY ==="
echo "  job scripts: $(ls -1 a02_preceding_s*.slurm a02_same_time_s*.slurm 2>/dev/null | wc -l) (expect 12)"
echo "  smoke run dir kept at: $(ls -d $PKG/runs/a02_smoke 2>/dev/null || echo none)"
echo "  partition state:"
sinfo -p hgpu2p -o "   %12P %8a %6D %26N %8t" 2>&1 | head -6
echo "  my current jobs before submit:"
squeue -u "$USER" -h -o "   %.10i %.16j %.8T" 2>&1 | head -8

echo "=== B REMOVE SMOKE RUN DIR (frees the name, keeps nothing needed) ==="
rm -rf $PKG/runs/a02_smoke
echo "  done"

echo "=== C SUBMIT 12 JOBS ==="
for SEED in 42 43 44 45 46 47; do
  for ARM in preceding same_time; do
    S=$(sbatch --parsable a02_${ARM}_s${SEED}.slurm 2>&1)
    printf "  %-24s -> jobid %s\n" "a02_${ARM}_s${SEED}" "$S"
    echo "$S" >> $PKG/.a02_jobids
  done
done

echo "=== D QUEUE STATE (30 s after submit) ==="
sleep 30
squeue -u "$USER" -o "%.10i %.18j %.9P %.8T %.10M %.20R" 2>&1 | grep -E "a02_|JOBID"

echo "=== E COUNT ==="
echo "  a02 jobs in queue: $(squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -c '^a02_')"
echo "  submitted job ids recorded in $PKG/.a02_jobids"
