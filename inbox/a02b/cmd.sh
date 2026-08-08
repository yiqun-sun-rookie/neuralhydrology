#!/bin/bash
# a02b seq=5 : are all 12 done?
export LC_ALL=C
PKG=/data1/home/$USER/nature_1st_a02

echo "=== A QUEUE ==="
timeout 25 squeue -u "$USER" -o "%.10i %.16j %.8T %.10M" 2>&1 | grep -E "a02_|JOBID" || echo "  (no a02 jobs in queue)"

echo "=== B FINAL STATES ==="
timeout 40 sacct -S 2026-08-07 -u "$USER" -X --format=JobID%9,JobName%13,State%11,ExitCode%7,Elapsed%9 2>&1 | grep -E "a02_(pre|sam)|JobID|----"

echo "=== C BEST METRICS (all 12) ==="
timeout 40 bash -c 'for d in '"$PKG"'/runs/a02_*/; do
  [ -f "$d/best_metrics.json" ] || continue
  printf "  %-24s %s\n" "$(basename $d)" "$(python -c "
import json,sys
m=json.load(open(sys.argv[1]))
print(f\"epoch={m[chr(39)]+chr(39)}\" if False else f\"epoch={m[\\\"epoch\\\"]:<3d} median_nse={m[\\\"median_nse\\\"]:.6f} n={m[\\\"n_stations\\\"]}\")
" "$d/best_metrics.json" 2>/dev/null || head -c 200 $d/best_metrics.json)"
done' 2>&1

echo "=== D DONE MARKERS IN LOGS ==="
timeout 40 bash -c 'for f in '"$PKG"'/logs/a02_pre_s4*.out '"$PKG"'/logs/a02_sam_s4*.out; do
  [ -f "$f" ] || continue
  printf "  %-24s %s\n" "$(basename $f .out)" "$(grep -a "Best median NSE\|Done (exit" "$f" | tail -2 | tr "\n" " | ")"
done' 2>&1

echo "=== E TARBALLS UNDER runs/ ==="
timeout 25 ls -la "$PKG/runs/"*.tar.gz 2>&1 | awk '{print "  ",$9,$5}'
