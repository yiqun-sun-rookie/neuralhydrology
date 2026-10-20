#!/bin/bash
set -eo pipefail
date -u
hostname
id -un
sinfo -p hcore40,hcpu48 -o '%P %a %l %D %t'
scontrol show partition hcore40
for p in /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python /data1/home/sunyiq/china_tws_haihe_recovery01_20261020; do
  if [ -e "$p" ]; then ls -ld "$p"; else printf 'ABSENT %s\n' "$p"; fi
done
printf 'HAIHE_PROBE_COMPLETE\n'
