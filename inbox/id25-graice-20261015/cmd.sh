#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_graice_lstmnosif_20261015_001
printf 'ROOT_EXISTS='
if [ -e "$root" ]; then echo YES; else echo NO; fi
printf 'BASE_PYTHON='
ls -l /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
printf 'PARTITIONS
'
sinfo -p hcpu48y,hgpu2p -o '%P|%a|%D|%t|%C'
printf 'THIS_JOB_NAME
'
squeue -h -u sunyiq -n id25_graice_261015 -o '%i|%j|%T|%R'
printf 'END_PREFLIGHT
'
