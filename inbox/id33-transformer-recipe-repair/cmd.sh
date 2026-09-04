#!/usr/bin/env bash
# ID33 seq=2 : submit the six recipe-repair arms. Submission only, no waiting loop.
set -o pipefail
ID33=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ID33" || exit 1
mkdir -p logs/33_transformer_recipe_repair results/33_transformer_recipe_repair/_reports
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final
echo "=== A. PRE-SUBMIT AUDIT ==="; date -Is
python -m src.transformer_recipe_repair.scripts.audit_configs 2>&1 || { echo AUDIT_FAILED; exit 1; }
echo "=== B. PARTITION ==="
sinfo -o "%.10P %.6a %.6D %.6t %.30N" 2>&1 | grep -E 'PARTITION|hgpu2p' || true
echo "=== C. SUBMIT ==="
SUB=""; FAIL=""
for ARM in T1 T2 T3 T4 T5 L33; do
  out=$(EXPERIMENT_ID="$ARM" sbatch --export=ALL,EXPERIMENT_ID="$ARM" \
        --job-name="id33_${ARM}" src/transformer_recipe_repair/hpc/submit_repair_arm.slurm 2>&1)
  jid=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  if [ -n "$jid" ]; then echo "  $ARM -> $jid"; SUB="$SUB $ARM:$jid"; else echo "  $ARM -> SUBMIT_FAILED"; echo "$out" | head -4; FAIL="$FAIL $ARM"; fi
done
echo "SUBMITTED:$SUB"; echo "FAILED:$FAIL"
echo "=== D. QUEUE ==="
squeue -u "$USER" -o "%.10i %.14j %.10P %.2t %.11M %.20R" 2>&1 | grep -E 'JOBID|id33' | head -10 || true
echo "=== E. ISOLATION ==="
sha256sum /data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo/results/30_modern_transformer_moe/D01/modern_transformer_moe_D01_dense_d128_l4_s100_2026_0827_1955_ep30/validation/model_epoch030/validation_metrics.csv 2>&1 | cut -c1-64
echo ID33_SUBMIT_SEQ2_COMPLETE
