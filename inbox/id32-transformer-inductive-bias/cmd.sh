#!/usr/bin/env bash
# ID32 seq=7 : emit the eight per-basin epoch-30 tables for independent local statistics.
set -o pipefail
ID32=/data1/home/sunyiq/id32_transformer_inductive_bias_20260902/repo
ID30=/data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo
R32="$ID32/results/32_transformer_inductive_bias"
R30="$ID30/results/30_modern_transformer_moe"

echo "=== A. STAMP ==="
date -Is

echo "=== B. ARM MEDIANS FROM THE BOUND METRICS ARTIFACTS ==="
python - "$R32" <<'PY' 2>&1 || true
import json, sys
from pathlib import Path
res = Path(sys.argv[1])
for arm in ("R01","T02","T03","T04","T05","L01"):
    hits = sorted((res/arm).glob("*/epoch030_metrics.json")) if (res/arm).is_dir() else []
    if not hits: print(arm, "NO_ARTIFACT"); continue
    v = json.loads(hits[0].read_text(encoding="utf-8"))
    print("%-4s basins=%d median=%.6f  run=%s" % (arm, v["basin_count"], v["median_nse"], hits[0].parent.name))
PY

echo "=== C. TABLES ==="
emit () {  # $1=tag  $2=csv path
  echo "###TABLE_BEGIN $1"
  if test -f "$2"; then cat "$2"; else echo "MISSING $2"; fi
  echo "###TABLE_END $1"
}
for arm in R01 T02 T03 T04 T05 L01; do
  f=$(find "$R32/$arm" -path '*/validation/model_epoch030/validation_metrics.csv' 2>/dev/null | head -1)
  emit "$arm" "$f"
done
D01=$(find "$R30/D01" -path '*/validation/model_epoch030/validation_metrics.csv' 2>/dev/null | head -1)
B01=$(find "$R30/B01" -path '*/validation/model_epoch030/validation_metrics.csv' 2>/dev/null | head -1)
emit "D01" "$D01"
emit "B01" "$B01"

echo "=== D. ISOLATION ==="
echo -n "ID31 DL01 ep30 ckpt: "
sha256sum "/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo/results/31_hydrologic_dynamic_tokens/DL01/hydrologic_dynamic_tokens_DL01_learned_end_to_end_s100_2026_0831_1223_ep30/model_epoch030.pt" 2>&1 | cut -c1-64
echo "ID32_TABLES_SEQ7_COMPLETE"
