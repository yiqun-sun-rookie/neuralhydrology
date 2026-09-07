#!/bin/bash
# attrswap-daily seq=9 -- READ-ONLY: structure of the Caravan dataset on the HPC (for the forcing-swap plan). No du/find over the whole tree.
set -o pipefail
date "+wallclock %F %T %z"
C=/data1/home/sunyiq/neuralhydrology/data/Caravan/Caravan
echo "=== A. top ==="; ls -la "$C" 2>&1 | head -20
echo "=== B. subsets ==="; ls "$C/timeseries/csv" 2>&1 | head -20; ls "$C/attributes" 2>&1 | head -20
echo "=== C. camels subset ==="; n=$(ls "$C/timeseries/csv/camels" 2>/dev/null | wc -l); echo "camels csv files: $n"; ls "$C/timeseries/csv/camels" 2>/dev/null | head -3
echo "=== D. sample header + first/last rows ==="; f=$(ls "$C/timeseries/csv/camels"/*.csv 2>/dev/null | head -1); echo "$f"; head -2 "$f" 2>/dev/null | cut -c1-1500; echo "..."; tail -1 "$f" 2>/dev/null | cut -c1-200; echo "rows: $(wc -l < "$f" 2>/dev/null)"
echo "=== E. attributes files ==="; ls -la "$C/attributes/camels" 2>&1 | head; head -1 "$C/attributes/camels/attributes_other_camels.csv" 2>/dev/null | cut -c1-400
echo "=== F. readme / version ==="; ls "$C"/*.md "$C"/*.txt 2>/dev/null; head -30 "$C"/README* 2>/dev/null | grep -iE "version|v1\.|era5|release|caravan" | head -8
echo "=== G. netcdf present? ==="; ls "$C/timeseries" 2>&1; ls "$C/timeseries/netcdf/camels" 2>/dev/null | head -2
echo "=== DONE ==="
