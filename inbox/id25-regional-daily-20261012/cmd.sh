#!/usr/bin/env bash
set -eo pipefail
printf 'TIME '; date -u
printf 'USER '; id -un
squeue -u "$USER" -h -o '%i|%j|%T|%P|%R'
sinfo -p hcpu48,hgpu2p -N -O nodelist,partition,gres:14,gresused:24,cpusstate
root=/data1/home/sunyiq/id25_regional_daily_storage_20261012_001
if [ -e "$root" ]; then printf 'CAMPAIGN_ROOT_EXISTS\n'; else printf 'CAMPAIGN_ROOT_FREE\n'; fi
if [ -f /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh ]; then printf 'CONDA_SH_PRESENT\n'; fi
