#!/usr/bin/env bash
set -o pipefail
echo "=== STAMP ==="; date -Is
ID33=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
echo "=== A. RERUN JOBS ==="
sacct -j 222800,222801 -X --format=JobID%9,JobName%9,State%11,ExitCode%7,Elapsed%10,NodeList%8 2>&1 || true
squeue -j 222800,222801 -o "%.9i %.10j %.2t %.11M %.20R %.20S" 2>&1 || true
echo "=== B. REMOTE FILE HASHES (must match local) ==="
cd "$ID33"
for f in neuralhydrology/modelzoo/recipe_fixed_transformer.py \
         src/transformer_recipe_repair/scripts/run_development.py \
         src/transformer_recipe_repair/scripts/audit_configs.py \
         src/transformer_recipe_repair/registry/experiments.csv \
         src/transformer_recipe_repair/hpc/submit_packed_arms.slurm; do sha256sum "$f" 2>&1; done
echo "=== C. PRESERVED FAILED EVIDENCE ==="
ls -1 results/33_transformer_recipe_repair/_superseded_20260904/ 2>&1 | head -10 || true
echo "  invocations preserved: $(ls -1 results/33_transformer_recipe_repair/_superseded_20260904/_invocations/ 2>/dev/null | wc -l)"
echo "=== D. CALIBRATION ARTIFACTS (COMPLETE manifests) ==="
for a in C1 C2; do
  f=$(find results/33_transformer_recipe_repair/$a -name 'epoch030_metrics.json' 2>/dev/null | head -1)
  test -n "$f" && sha256sum "$f" 2>&1 || echo "  $a no artifact"
done
echo "=== E. GPU UTILISATION SAMPLER (is the packed job filling the card) ==="
for f in logs/33_transformer_recipe_repair/utilisation-*.csv; do
  test -f "$f" || continue
  n=$(( $(wc -l < "$f") - 1 ))
  echo "  $f samples=$n"
  [ "$n" -gt 0 ] && awk -F, 'NR>1{u+=$2;m+=$3;c++} END{if(c)printf("    gpu_util mean=%.1f%%  mem mean=%.0f MiB of %s\n",u/c,m/c,$4)}' "$f"
done
echo "=== F. ID30/ID31/ID32 UNTOUCHED ==="
sha256sum /data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo/results/30_modern_transformer_moe/D01/modern_transformer_moe_D01_dense_d128_l4_s100_2026_0827_1955_ep30/validation/model_epoch030/validation_metrics.csv 2>&1 | cut -c1-64
sha256sum /data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo/results/31_hydrologic_dynamic_tokens/DL01/hydrologic_dynamic_tokens_DL01_learned_end_to_end_s100_2026_0831_1223_ep30/model_epoch030.pt 2>&1 | cut -c1-64
test -d /data1/home/sunyiq/id32_transformer_inductive_bias_20260902/repo && echo "ID32 root intact"
echo HANDOFF_FACTS_COMPLETE
