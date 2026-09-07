#!/bin/bash
# attrswap-daily seq=8 -- READ-ONLY probe for the next experiment (forcing swap): what daily forcing products exist on the HPC.
set -o pipefail
date "+wallclock %F %T %z"
echo "=== A. ~/neuralhydrology/data top level ==="
ls -la /data1/home/sunyiq/neuralhydrology/data/ 2>&1 | head -40
echo "=== B. caravan / era5 / haihe candidates (depth 2) ==="
find /data1/home/sunyiq/neuralhydrology/data -maxdepth 2 \( -iname "*caravan*" -o -iname "*era5*" -o -iname "*haihe*" -o -iname "*forcing*" \) 2>/dev/null | head -30
echo "=== C. sizes of candidates ==="
for d in /data1/home/sunyiq/neuralhydrology/data/caravan* /data1/home/sunyiq/neuralhydrology/data/haihe* /data1/home/sunyiq/neuralhydrology/data/*era5*; do [ -e "$d" ] && du -sh "$d" 2>/dev/null; done
echo "=== D. camels_us basin_mean_forcing products ==="
ls /data1/home/sunyiq/neuralhydrology/data/camels_us/basin_mean_forcing/ 2>&1
echo "=== E. caravan camels subset (if present) ==="
for d in /data1/home/sunyiq/neuralhydrology/data/caravan*; do [ -d "$d" ] && { find "$d" -maxdepth 3 -type d | head -20; find "$d" -maxdepth 4 -type f -name "*.csv" | head -3; find "$d" -maxdepth 4 -type f -name "*camels*" | head -5; }; done
echo "=== F. attrswap jobs final accounting ==="
sacct -j 222824,222825,222826,222827,222828,222829,222830 -X --format=JobID%9,JobName%28,State%10,ExitCode%8,Elapsed%10,CPUTime%10 2>&1
echo "=== DONE ==="
