#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
echo "=== STAMP ==="; date -Is
echo "=== CURRENT HASHES OF TRACKED IMPLEMENTATION FILES ==="
cd $ROOT || exit 1
for f in neuralhydrology/modelzoo/__init__.py neuralhydrology/modelzoo/cudalstm.py neuralhydrology/modelzoo/modern_causal_transformer.py neuralhydrology/modelzoo/recency_biased_transformer.py neuralhydrology/modelzoo/recipe_fixed_transformer.py neuralhydrology/utils/config.py src/transformer_recipe_repair/hpc/submit_repair_arm.slurm src/transformer_recipe_repair/registry/experiments.csv src/transformer_recipe_repair/scripts/audit_configs.py src/transformer_recipe_repair/scripts/run_development.py; do
  sha256sum "$f" 2>&1 || true
done
echo "=== CONFIG HASHES ==="
sha256sum src/transformer_recipe_repair/configs/*.yml 2>&1 || true
echo "=== T5 MANIFEST TAIL ==="
grep -E '"(error|status|training_return_code|run_id)"' results/33_transformer_recipe_repair/_invocations/id33_T5_s100_slurm220494/run_manifest.json | head -6 || true
echo "=== T5 DATA ACCESS ==="
grep -oE '"status": "[A-Z]+"' results/33_transformer_recipe_repair/_invocations/id33_T5_s100_slurm220494/run_manifest.json | head -4 || true
echo "ID33_HASHCHECK_COMPLETE"
