#!/bin/bash
# haihe Gangnan B': status + replace OWN pending aggregate job 245972 with an MKL-fixed copy (playbook iron rule 3).
# Touches only jobs 245970/245971/245972 and files under ROOT. Idempotent via marker.
set -o pipefail
ROOT=/data1/home/sunyiq/haihe_gangnan_bprime
OLD_AGG=245972
ARRAY=245971

echo "=== STATUS ==="
date -Is
squeue -j 245970,245971,245972 -h -o '%i %P %T %R %S' 2>&1 || true
sacct -X -n -j 245970,245971,245972 --format=JobID%16,State%12,ExitCode,NodeList%10,Elapsed 2>&1 | head -40

echo "=== FIX AGGREGATE ==="
MARK="$ROOT/logs/aggregate_mkl_resubmitted"
if [ -f "$MARK" ]; then
    echo "ALREADY_RESUBMITTED: $(cat $MARK)"
    exit 0
fi
ST=$(squeue -j $OLD_AGG -h -o '%T' 2>/dev/null)
echo "old aggregate state: ${ST:-GONE}"
[ "$ST" = "PENDING" ] || { echo "OLD_AGG_NOT_PENDING -- leaving it alone"; exit 0; }

cd "$ROOT" || exit 1
cp slurm/run_aggregate.slurm slurm/run_aggregate.v1.slurm
sed -i '/^conda activate/a export MKL_SERVICE_FORCE_INTEL=1' slurm/run_aggregate.slurm
sed -i '/^conda activate/a export MKL_THREADING_LAYER=GNU' slurm/run_aggregate.slurm
grep -c '^export MKL_' slurm/run_aggregate.slurm | grep -qx 2 || { echo "SED_FAILED"; exit 1; }
grep -n 'dependency\|^export MKL\|^conda activate\|-p hgpu' slurm/run_aggregate.slurm

scancel $OLD_AGG && echo "cancelled own pending $OLD_AGG"
out=$(sbatch slurm/run_aggregate.slurm 2>&1); echo "$out" | head -5
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$JID" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "run_aggregate_mkl $JID $(date -Is) replaces $OLD_AGG" >> "$ROOT/logs/submissions.txt"
echo "$JID" > "$MARK"
squeue -j $JID -h -o '%i %T %R' 2>&1
echo "AGG_RESUBMITTED new=$JID"
