#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001
printf 'RDS04_/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001_EXISTS='; if test -e "$root"; then echo yes; ls -l "$root"; else echo no; fi
for f in /data1/home/sunyiq/id25_regional_daily_storage_20261012_001/inputs/inputs.npz /data1/home/sunyiq/id25_regional_daily_storage_20261012_001/inputs/transforms.json /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python; do ls -l "$f"; done
timeout 30 squeue -h -u sunyiq -n id25_rds04_261021 -o '%i|%j|%T|%R'
echo READ_ONLY_PATH_CHECK_DONE
