#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_dielmelt_20261015_001
printf 'HOST='; hostname
if [ -e "$root" ]; then echo ROOT_ALREADY_EXISTS; ls -ld "$root"; else echo ROOT_FRESH; fi
ls -l /data1/home/sunyiq/id25_regional_daily_storage_20261012_001/inputs/inputs.npz /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
squeue -h -u sunyiq -n id25_diel_261015 -o '%i|%j|%T|%M|%R'
sinfo -p hgpu2p -h -o '%P|%a|%l|%D|%t'
