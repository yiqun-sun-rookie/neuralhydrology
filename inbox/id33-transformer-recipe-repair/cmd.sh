#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
echo "=== STAMP ==="; date -Is
echo "=== A. MANIFEST FULL (one failed arm) ==="
sed -e 's/[[:space:]]\+/ /g' $ROOT/results/33_transformer_recipe_repair/_invocations/id33_T2_s100_slurm220491/run_manifest.json | head -80 || true
echo "=== B. FAILURE REASON PER ARM ==="
for a in T1 T2 T3 T4 L33; do
  echo "--- $a"
  m=$(ls -1d $ROOT/results/33_transformer_recipe_repair/_invocations/id33_${a}_s100_slurm*/ 2>/dev/null | head -1)
  grep -oE '"(error|failure_reason|message|traceback)"[^,]{0,400}' "$m/run_manifest.json" 2>/dev/null | head -5 || true
done
echo "=== C. SLURM ERR TAILS ==="
for j in 220490 220491 220492 220493 220495; do
  echo "--- job $j"
  f=$(ls -1 $ROOT/logs/*${j}*.err $ROOT/*${j}*.err /data1/home/sunyiq/id33_transformer_recipe_repair_20260904/logs/*${j}*.err 2>/dev/null | head -1)
  echo "  file=$f"
  [ -n "$f" ] && tail -25 "$f" || true
done
echo "=== D. VALIDATION CSV PRESENCE ==="
for a in T1 T2 T3 T4 T5 L33; do
  n=$(ls -1 $ROOT/results/33_transformer_recipe_repair/$a/*/validation/model_epoch0*/validation_metrics.csv 2>/dev/null | wc -l)
  echo "$a: $n epoch-dirs with metrics csv"
  ls -1 $ROOT/results/33_transformer_recipe_repair/$a/*/validation/ 2>/dev/null | tail -4 || true
done
echo "ID33_DIAG_COMPLETE"
