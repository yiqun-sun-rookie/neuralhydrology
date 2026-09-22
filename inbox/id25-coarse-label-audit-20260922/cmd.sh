#!/bin/bash
set -eo pipefail
echo '=== identity ==='
hostname
date -u +'%Y-%m-%dT%H:%M:%SZ'
echo '=== scheduler ==='
sinfo -h -p hcpu48 -o '%P %a %l %D %t' 2>&1
echo '=== permitted coarse metadata ==='
for root in "$HOME/neuralhydrology" /data1/home/sunyiq/neuralhydrology; do
  for rel in data/id25/multisource/spatial_folds_primary_land_v1/folds.json results/25_global_flood_hierarchy/split_contrast_checkerboard_v1/folds/folds_checkerboard.json results/25_global_flood_hierarchy/formal_portfolio_primary_land_production_v2_statics_lr1e3/formal_portfolio_manifest.json; do
    if [ -f "$root/$rel" ]; then
      stat -c '%n %s bytes' "$root/$rel"
    else
      echo "MISSING $root/$rel"
    fi
  done
done
