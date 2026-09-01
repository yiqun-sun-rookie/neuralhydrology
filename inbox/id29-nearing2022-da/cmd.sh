set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
if [ -f "$ROOT/closure_20260810/aggregation/evaluations/time_split_vs_author.csv" ]; then
  echo "already aggregated, skip"; exit 0
fi
N=$(squeue -u sunyiq -h -o '%j' 2>/dev/null | grep -c 'N22-aggeval2' || true)
echo "existing N22-aggeval2 in queue: $N"
if [ "$N" = "0" ]; then
  sbatch --job-name=N22-aggeval2 --exclude=ngu002,ngu101 \
    --export=ALL,AGGREGATION_KIND=evaluations \
    src/29_nearing2022_da_ar/hpc/run_registered_aggregation.slurm
fi
squeue -u sunyiq -h -o '%.12i %.16j %.9T %R' 2>/dev/null | grep -E 'N22-aggeval2' || echo 'not in queue after submit'
exit 0
