#!/bin/bash
# a02b seq=10 : ship the 12 tiny dqdt_stats.json inline (115 bytes each).
export LC_ALL=C
PKG=/data1/home/$USER/nature_1st_a02
for d in "$PKG"/runs/a02_*/; do
  [ -f "$d/dqdt_stats.json" ] || continue
  echo "##FILE $(basename $d)"
  cat "$d/dqdt_stats.json"
  echo ""
done
