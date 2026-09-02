#!/usr/bin/env bash
# ID32 seq=4 : watch the six arms; dump validation tables for finished arms.
set -o pipefail
ID32=/data1/home/sunyiq/id32_transformer_inductive_bias_20260902/repo

echo "=== A. SACCT ==="
sacct -j 218680,218681,218682,218683,218684,218685 -X --format=JobID%10,JobName%12,State%12,ExitCode%8,Elapsed%10,NodeList%10 2>&1 || true

echo "=== B. MANIFEST ==="
for A in R01 T02 T03 T04 T05 L01; do
  M=$(ls $ID32/results/32_transformer_inductive_bias/_invocations/id32_${A}_s100_slurm*/run_manifest.json 2>/dev/null | head -1)
  echo "--- $A manifest=${M:-none}"
  if [ -n "$M" ]; then
    grep -E '"(status|training_return_code|source_hash|source_tree_hash|hash)"' "$M" || true
  fi
done

echo "=== C. PROGRESS ==="
for A in R01 T02 T03 T04 T05 L01; do
  D=$(ls -d $ID32/results/32_transformer_inductive_bias/_invocations/id32_${A}_s100_slurm* 2>/dev/null | head -1)
  echo "--- $A"
  if [ -n "$D" ] && [ -f "$D/output.log" ]; then
    tail -c 300000 "$D/output.log" | grep -oE 'Epoch [0-9]+ average loss: [0-9.]+' | tail -1 || true
    tail -2 "$D/output.log" || true
  fi
done

echo "=== D. VALIDATION TABLES (finished arms only) ==="
for A in R01 T02 T03 T04 T05 L01; do
  V=$(ls $ID32/results/32_transformer_inductive_bias/${A}/*/validation/model_epoch030/validation_metrics.csv 2>/dev/null | head -1)
  if [ -n "$V" ]; then
    echo "<<<BEGIN $A $V"
    cat "$V" || true
    echo "<<<END $A"
  else
    echo "--- $A: no epoch-30 validation table yet"
  fi
done
echo "ID32_WATCH_SEQ4_COMPLETE"
