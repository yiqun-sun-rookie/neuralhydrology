#!/bin/bash
# Read-only: base64 the finished-family (zhenjiang/jiangyin) impact tables.
set -o pipefail
SRC=/data1/home/sunyiq/zhenjiang_oyv_v1/ladder_impact
sha256sum "$SRC"/ladder_cost_summary.csv "$SRC"/station_ranking.csv
for f in station_ranking.csv ladder_cost_summary.csv; do
  echo "===BEGIN $f==="
  base64 -w 200 "$SRC/$f"
  echo "===END $f==="
done
echo "=== DONE ==="