#!/bin/bash
set -o pipefail
echo "=== V5 CSV SEARCH ==="
ls ~/neuralhydrology/results/10_global_conceptual_model_benchmark/ 2>&1 | head -15
find ~/neuralhydrology/results/10_global_conceptual_model_benchmark -maxdepth 3 -name "*.csv" 2>/dev/null | grep -i "hbv" | head -10 || true
echo "=== MAURER REGION DIRS ==="
ls ~/neuralhydrology/data/camels_us/basin_mean_forcing/maurer/ 2>&1 | head -20
echo "=== 27 BASIN FILE CHECK ==="
BASINS="01047000 01440000 01543000 01545600 01568000 01596500 01644000 02111180 02143040 02196000 02221525 02374500 02479560 03050000 03076600 03384450 03500000 04015330 06311000 06803530 06910800 11523200 12040500 12073500 12167000 12488500 14182500"
MISS=0; OK=0
for b in $BASINS; do
  F=$(find ~/neuralhydrology/data/camels_us/basin_mean_forcing/maurer -name "${b}_*" 2>/dev/null | head -1)
  Q=$(find ~/neuralhydrology/data/camels_us/usgs_streamflow -name "${b}_*" 2>/dev/null | head -1)
  if [ -z "$F" ] || [ -z "$Q" ]; then echo "MISSING $b forcing=${F:-NO} flow=${Q:-NO}"; MISS=$((MISS+1)); else OK=$((OK+1)); fi
done
echo "ok=$OK missing=$MISS"
echo "=== SAMPLE FILE HEAD ==="
find ~/neuralhydrology/data/camels_us/basin_mean_forcing/maurer -name "01047000_*" 2>/dev/null | head -1 | xargs head -4 2>/dev/null || true
echo "=== ATTRS ==="
ls ~/neuralhydrology/data/camels_us/camels_attributes_v2.0/ 2>&1 | head -8
