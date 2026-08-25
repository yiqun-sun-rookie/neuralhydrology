#!/bin/bash
set -o pipefail
echo "=== A. all CPU partitions right now ==="
sinfo -o "%18P %8a %6D %10t %N" 2>&1 | grep -E 'PARTITION|hcpu' | head -12 || true
echo "=== B. idle node counts ==="
for P in hcpu48 hcpu48y; do
  N=$(sinfo -h -p $P -t idle -o "%D" 2>/dev/null | paste -sd+ | bc 2>/dev/null)
  echo "$P idle nodes: ${N:-0}"
done
echo "=== C. do hcpu48 and hcpu48y run the same OS? (must match for numba comparability) ==="
sinfo -h -p hcpu48y -t idle -o "%N" 2>&1 | head -2 || true
echo "=== D. queue depth ahead of me on hcpu48 ==="
squeue -p hcpu48 -h -t PENDING -o "%i" 2>/dev/null | wc -l
squeue -p hcpu48 -h -t RUNNING -o "%i" 2>/dev/null | wc -l
echo "=== E. resubmit the gate to BOTH cpu partitions, whole node, shorter walltime ==="
ROOT=~/kuwei_paired
scancel 212027 2>&1 && echo "cancelled 212027" || true
sed -i 's|^#SBATCH -p hcpu48$|#SBATCH -p hcpu48,hcpu48y|; s|^#SBATCH -t 02:00:00$|#SBATCH -t 01:30:00|' $ROOT/gate/gate.slurm
grep -E '^#SBATCH' $ROOT/gate/gate.slurm | head -8
cd $ROOT/gate && sbatch gate.slurm 2>&1 | tee $ROOT/gate/gate_jobid.txt || echo "sbatch FAILED"
squeue -u ${USER} -n kuwei-gate -o "%.10i %.12j %.10P %.8T %R" 2>&1 | head -4 || true
echo "=== DONE ==="
