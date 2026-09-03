#!/usr/bin/env bash
# ID32 seq=8 : training curves for R01 and T05, to see whether dropout actually bit.
set -o pipefail
R32=/data1/home/sunyiq/id32_transformer_inductive_bias_20260902/repo/results/32_transformer_inductive_bias
echo "=== STAMP ==="; date -Is
for arm in R01 T05; do
  f=$(find "$R32/$arm" -name output.log -type f 2>/dev/null | head -1)
  echo "=== $arm CURVE  ($f) ==="
  if test -n "$f"; then
    grep -E 'Epoch [0-9]+ average loss|Epoch [0-9]+ average validation' "$f" 2>&1 || true
  else echo "LOG_MISSING"; fi
done
echo "ID32_CURVES_SEQ8_COMPLETE"
