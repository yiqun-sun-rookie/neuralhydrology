#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
echo "=== STAMP ==="; date -Is
echo "=== A. SACCT ==="
sacct -j 220494,220658,220659 -X --format=JobID%10,JobName%12,State%12,ExitCode%8,Elapsed%11,NodeList%9 2>&1 || true
echo "=== B. T5 EPOCHS ==="
f=$(ls -1 $ROOT/results/33_transformer_recipe_repair/T5/*/output.log 2>/dev/null | head -1)
grep -E "Median validation" "$f" | tail -8 || true
echo "=== C. T5 EPOCH30 DUMP ==="
c=$(ls -1 $ROOT/results/33_transformer_recipe_repair/T5/*/validation/model_epoch030/validation_metrics.csv 2>/dev/null | head -1)
echo "file=$c"
echo "###ARM T5"
awk -F, 'NR==1{for(i=1;i<=NF;i++){if($i=="basin")b=i;if($i=="NSE")n=i};next}{print $b","$n}' "$c" 2>/dev/null | head -540 || true
echo "=== D. C1/C2 PROGRESS ==="
for a in C1 C2; do
  echo "--- $a"
  g=$(ls -1 $ROOT/results/33_transformer_recipe_repair/$a/*/output.log 2>/dev/null | head -1)
  grep -E "Median validation" "$g" | tail -3 || true
done
echo "ID33_T5_COMPLETE"
