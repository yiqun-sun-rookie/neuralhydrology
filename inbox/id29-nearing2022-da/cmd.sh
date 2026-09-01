set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
date --iso-8601=seconds
if [ -f "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json" ]; then
  echo "gate artifact already PRESENT, skip"; exit 0
fi
N=$(squeue -u sunyiq -h -o '%j' 2>/dev/null | grep -c 'N22-gate2' || true)
echo "existing N22-gate2 count=$N"
if [ "$N" = "0" ]; then
  sbatch --job-name=N22-gate2 --exclude=ngu002,ngu101 src/29_nearing2022_da_ar/hpc/run_registered_numerical_gate.slurm
fi
squeue -u sunyiq -h -o '%.12i %.16j %.9T %R' 2>/dev/null | grep -E 'N22-gate2' || echo 'gate2 not in queue'
exit 0
