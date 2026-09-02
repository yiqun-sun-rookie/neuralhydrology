#!/usr/bin/env bash
# ID32 seq=6 : final status of the six arms; dump T04/T05 validation tables (read-only).
set -o pipefail
ID32=/data1/home/sunyiq/id32_transformer_inductive_bias_20260902/repo

echo "=== A. SACCT ==="
sacct -j 218680,218681,218682,218683,218684,218685 -X --format=JobID%10,JobName%12,State%12,ExitCode%8,Elapsed%10,NodeList%10 2>&1 || true

echo "=== B. MANIFEST T04 T05 ==="
for A in T04 T05; do
  M=$(ls $ID32/results/32_transformer_inductive_bias/_invocations/id32_${A}_s100_slurm*/run_manifest.json 2>/dev/null | head -1)
  echo "--- $A manifest=${M:-none}"
  if [ -n "$M" ]; then
    cat "$M" || true
  fi
done

echo "=== C. VALIDATION TABLES T04 T05 ==="
for A in T04 T05; do
  V=$(ls $ID32/results/32_transformer_inductive_bias/${A}/*/validation/model_epoch030/validation_metrics.csv 2>/dev/null | head -1)
  if [ -n "$V" ]; then
    echo "<<<BEGIN $A $V"
    cat "$V" || true
    echo "<<<END $A"
  else
    echo "--- $A: no epoch-30 validation table yet"
  fi
done
echo "ID32_WATCH_SEQ6_COMPLETE"
