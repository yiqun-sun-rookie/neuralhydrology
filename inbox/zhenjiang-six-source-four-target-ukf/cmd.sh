#!/bin/bash
set -o pipefail
OUT="/data1/home/sunyiq/zhenjiang_six_source_four_target_ukf_qr_learning_value_20260903"
printf '=== SNAPSHOT_TIME ===\n'; date -Is
for s in 17 29 43; do
  c="${OUT}/runs/qr_learning_value/s${s}/attempt_001/selection_block_sums.csv"
  if [ -f "$c" ]; then
    printf '=== CSV_BEGIN_s%s ===\n' "$s"
    cat "$c"
    printf '=== CSV_END_s%s ===\n' "$s"
  else
    printf 'CSV_ABSENT|s%s\n' "$s"
  fi
done
printf '=== MANIFESTS ===\n'
for s in 17 29 43; do
  m="${OUT}/runs/qr_learning_value/s${s}/attempt_001/completion_manifest.json"
  [ -f "$m" ] && { printf 'MANIFEST_s%s=' "$s"; cat "$m"; printf '\n'; } || true
done
printf '=== SNAPSHOT_END ===\n'; date -Is
exit 0
