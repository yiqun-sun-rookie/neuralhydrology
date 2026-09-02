#!/usr/bin/env bash
# ID32 seq=5 : watch the six arms; dump validation tables for finished arms + ID30 baselines (read-only).
set -o pipefail
ID32=/data1/home/sunyiq/id32_transformer_inductive_bias_20260902/repo
ID30=/data1/home/sunyiq/id30_modern_transformer_moe_20260827

echo "=== A. SACCT ==="
sacct -j 218680,218681,218682,218683,218684,218685 -X --format=JobID%10,JobName%12,State%12,ExitCode%8,Elapsed%10,NodeList%10 2>&1 || true

echo "=== B. MANIFEST ==="
for A in R01 T02 T03 T04 T05 L01; do
  M=$(ls $ID32/results/32_transformer_inductive_bias/_invocations/id32_${A}_s100_slurm*/run_manifest.json 2>/dev/null | head -1)
  echo "--- $A manifest=${M:-none}"
  if [ -n "$M" ]; then
    grep -E '"(status|training_return_code|source_tree_hash|source_hash|hash_before|hash_after)"' "$M" || true
  fi
done

echo "=== C. PROGRESS ==="
for A in R01 T02 T03 T04 T05 L01; do
  D=$(ls -d $ID32/results/32_transformer_inductive_bias/_invocations/id32_${A}_s100_slurm* 2>/dev/null | head -1)
  echo "--- $A dir=${D:-none}"
  if [ -n "$D" ]; then
    ls "$D" 2>/dev/null | head -20 || true
    for F in "$D"/output.log "$D"/*.out "$D"/*.err; do
      [ -f "$F" ] || continue
      echo "  [file] $F"
      tail -3 "$F" 2>/dev/null || true
    done
  fi
done

echo "=== D. ARM VALIDATION TABLES ==="
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

echo "=== E. ID30 BASELINES (read-only) ==="
for B in D01 B01; do
  V=$(find $ID30 -path "*${B}*/validation/model_epoch030/validation_metrics.csv" 2>/dev/null | head -1)
  echo "--- $B path=${V:-none}"
  if [ -n "$V" ]; then
    echo "<<<BEGIN BASE_$B $V"
    cat "$V" || true
    echo "<<<END BASE_$B"
  fi
done
echo "ID32_WATCH_SEQ5_COMPLETE"
