#!/bin/bash
# Read-only: fetch P3 outputs.
NEW=/data1/home/sunyiq/ohn_da_vs_ar_531_20261021
cd $NEW/results/p3 || exit 1
ls -la
echo "=== MEDIAN_BY_L ==="; cat p3_median_nse_by_L.csv
echo "=== PAIRED ==="; cat p3_paired_comparisons.csv
echo "=== VERDICTS ==="; cat p3_verdicts.json
echo "=== NBB_HEAD ==="; head -3 p3_nse_by_basin.csv; wc -l p3_nse_by_basin.csv
echo "=== P3 LOG ==="; tail -n 60 $NEW/logs/ohn_p3_score-246281.out
echo "=== P3 ERR ==="; tail -n 15 $NEW/logs/ohn_p3_score-246281.err
echo "SEQ84_DONE"
