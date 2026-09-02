#!/usr/bin/env bash
# ID32 seq=2 : submit the six single-factor ablation arms. Submission only; no waiting loop.
set -o pipefail
ID32=/data1/home/sunyiq/id32_transformer_inductive_bias_20260902/repo
cd "$ID32" || exit 1
mkdir -p logs/32_transformer_inductive_bias results/32_transformer_inductive_bias/_reports

echo "=== A. PRE-SUBMIT AUDIT ==="
date -Is
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -m src.transformer_inductive_bias.scripts.audit_configs 2>&1 || { echo AUDIT_FAILED; exit 1; }

echo "=== B. PARTITION STATE (sinfo, not squeue) ==="
sinfo -o "%.10P %.6a %.6D %.6t %.30N" 2>&1 | grep -E 'PARTITION|hgpu2p' || true

echo "=== C. SUBMIT SIX ARMS ==="
SUBMITTED=""
FAILED=""
for ARM in R01 T02 T03 T04 T05 L01; do
  out=$(EXPERIMENT_ID="$ARM" sbatch --export=ALL,EXPERIMENT_ID="$ARM" \
        --job-name="id32_${ARM}" src/transformer_inductive_bias/hpc/submit_ablation_arm.slurm 2>&1)
  jid=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  if [ -n "$jid" ]; then
    echo "  $ARM -> job $jid"
    SUBMITTED="$SUBMITTED $ARM:$jid"
  else
    echo "  $ARM -> SUBMIT_FAILED"
    echo "$out" | head -5
    FAILED="$FAILED $ARM"
  fi
done
echo "SUBMITTED:$SUBMITTED"
echo "FAILED:$FAILED"

echo "=== D. QUEUE STATE ==="
squeue -u "$USER" -o "%.10i %.14j %.10P %.2t %.11M %.20R" 2>&1 | head -20 || true

echo "=== E. ISOLATION RECHECK ==="
echo -n "ID31 DL01 epoch30 checkpoint: "
sha256sum /data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo/results/31_hydrologic_dynamic_tokens/DL01/hydrologic_dynamic_tokens_DL01_learned_end_to_end_s100_2026_0831_1223_ep30/model_epoch030.pt 2>&1 | cut -c1-64
echo -n "ID30 D01 epoch30 metrics:     "
sha256sum /data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo/results/30_modern_transformer_moe/D01/modern_transformer_moe_D01_dense_d128_l4_s100_2026_0827_1955_ep30/validation/model_epoch030/validation_metrics.csv 2>&1 | cut -c1-64
echo "ID32_SUBMIT_SEQ2_COMPLETE"
