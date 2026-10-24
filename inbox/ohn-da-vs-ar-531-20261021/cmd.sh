#!/bin/bash
# Read-only: per-basin NSE table and GPU-hour accounting for the report.
NEW=/data1/home/sunyiq/ohn_da_vs_ar_531_20261021
echo "=== SACCT ==="
sacct -X -n -P -j 246200,246201,246239,246240,246243,246378,246450,246280,246911,246281,246279 -o JobID,JobName,State,Elapsed,ElapsedRaw,NodeList 2>&1
echo "=== NSE_BY_BASIN ==="
cat $NEW/results/p3/p3_nse_by_basin.csv
echo "SEQ85_DONE"
