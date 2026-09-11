#!/bin/bash
# seq=49 failure diagnosis for seed jobs 225188 (s300) / 225189 (s400) / 225193 (s800); read-only
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date -Iseconds
for j in 225188 225189 225193; do
  echo "=== OUT $j (head 40) ==="; head -40 logs/33_transformer_recipe_repair/packed-$j.out 2>&1 || true
  echo "=== OUT $j (tail 30) ==="; tail -30 logs/33_transformer_recipe_repair/packed-$j.out 2>&1 || true
  echo "=== ERR $j (tail 30) ==="; tail -30 logs/33_transformer_recipe_repair/packed-$j.err 2>&1 || true
done
echo "=== RUN DIRS FOR FAILED SEEDS ==="
ls -d results/33_transformer_recipe_repair/*_s300/* results/33_transformer_recipe_repair/*_s400/* results/33_transformer_recipe_repair/*_s800/* 2>&1 || true
echo "=== INVOCATIONS ==="
ls results/33_transformer_recipe_repair/_invocations/ 2>&1 | grep -E 's300|s400|s800' || true
echo "=== NODE STATE ==="
sinfo -p hgpu2p,hgpu2 -N -o "%.10N %.8T %.20E" 2>&1 || true
echo "=== 225187 GPU CHECK (ngu010) ==="
head -5 logs/33_transformer_recipe_repair/utilisation-225187.csv 2>&1 || true
grep -iE 'cuda|device|gpu' logs/33_transformer_recipe_repair/packed-225187.out 2>/dev/null | head -10 || true
grep -m3 -iE 'cuda|device' results/33_transformer_recipe_repair/T2_s200/*/output.log 2>/dev/null || true
echo "=== SLURM SCRIPT GPU GUARD ==="
grep -nE 'FATAL|nvidia-smi|CUDA_VISIBLE|gres|partition|nodelist|exclude' src/transformer_recipe_repair/hpc/submit_packed_arms.slurm || true
