#!/bin/bash
# Read-only: base64 the six small n4_impact tables into the result body.
set -o pipefail
SRC=/data1/home/sunyiq/zhenjiang_oyv_v1/n4_impact
echo "pwd=$(pwd)"
for f in n4_station_ranking.csv n4_prediction_verdicts.csv n4_information_comparison.csv n4_summary.json completion_manifest.json n4_cost_summary.csv; do
  echo "===BEGIN $f==="
  base64 -w 200 "$SRC/$f"
  echo "===END $f==="
done
echo "=== DONE ==="