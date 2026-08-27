#!/bin/bash
# nature1st-attr-swap seq=102 -- 30-second GPU identity probe on the two idle nodes.
# NOT a training run: 1 cpu, 1 gpu, 5-minute wall limit, prints nvidia-smi and exits.
# Purpose: armJ (215195) is stuck behind other users' invisible jobs in hgpu2p with a
# two-day start estimate, while ngu009 (hgpu2) and ngu101 (hgpu4) sit fully idle.
# Moving armJ there is only safe if the card is the same RTX 3090 the other eight arms
# ran on. SLURM does not record the model, so measure it.
set -o pipefail
cd ~/hpc_mailbox || exit 1
mkdir -p inbox outbox

echo "=== A. WRITE PROBE SCRIPTS ==="
for spec in 'ngu009:hgpu2' 'ngu101:hgpu4'; do
  N=${spec%%:*}; P=${spec##*:}
  cat > inbox/gpucheck_${N}.slurm <<SL
#!/usr/bin/env bash
#SBATCH -J gpucheck_${N}
#SBATCH -p ${P}
#SBATCH --nodelist=${N}
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=1
#SBATCH --gres=gpu:1
#SBATCH -t 00:05:00
#SBATCH -o /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.out
#SBATCH -e /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.err
set -eo pipefail
echo "host=\$(hostname)"
nvidia-smi --query-gpu=index,name,driver_version,memory.total --format=csv,noheader || echo NVIDIA_SMI_FAILED
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -c "import torch;print('torch',torch.__version__,'cuda',torch.cuda.is_available(),'|',torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'NO GPU')"
SL
  echo "  wrote inbox/gpucheck_${N}.slurm"
done

echo "=== B. SUBMIT BOTH ==="
JIDS=''
for N in ngu009 ngu101; do
  out=$(sbatch inbox/gpucheck_${N}.slurm 2>&1); echo "  $N -> $out"
  j=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
  [ -n "$j" ] && JIDS="$JIDS $j"
done
echo "  jobids:$JIDS"
[ -n "$JIDS" ] || { echo "SUBMIT_FAILED for both"; exit 1; }

echo "=== C. WAIT (max 4 min) ==="
for i in $(seq 1 24); do
  LEFT=0
  for j in $JIDS; do squeue -j $j -h -o '%i' 2>/dev/null | grep -q . && LEFT=$((LEFT+1)); done
  [ $((i % 4)) -eq 0 ] && echo "  t=$((i*10))s still queued/running: $LEFT"
  [ "$LEFT" -eq 0 ] && break
  sleep 10
done

echo "=== D. RESULTS ==="
for j in $JIDS; do
  echo "---- job $j ----"
  sacct -j $j -X --format=JobID%10,JobName%16,State%12,ExitCode%8,Elapsed%10,NodeList%8 2>&1 | tail -2
  [ -f outbox/slurm_${j}.out ] && cat outbox/slurm_${j}.out 2>&1 | head -12 || echo '  (no stdout)'
  [ -s outbox/slurm_${j}.err ] && { echo '  -- stderr --'; head -6 outbox/slurm_${j}.err; } || true
  rm -f outbox/slurm_${j}.out outbox/slurm_${j}.err
done

echo "=== E. REFERENCE: hgpu2p card, measured earlier on ngu010 ==="
echo "  torch 2.4.0 cuda True NVIDIA GeForce RTX 3090   (job 201451, 2026-08-06)"

echo "=== F. armJ STILL PENDING? ==="
squeue -j 215195 -o '%.10i %.9T %.20S %.20R' 2>&1
echo "=== END seq=102 ==="
