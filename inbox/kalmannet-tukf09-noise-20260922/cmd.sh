#!/usr/bin/env bash
set -eo pipefail
date -u '+%Y-%m-%dT%H:%M:%SZ'
hostname
id -un
printf 'CURRENT_USER_JOBS\n'
squeue -u sunyiq -h -o '%i|%j|%T|%P|%C|%D|%R|%Z'
printf 'PARTITIONS\n'
scontrol show partition hcpu48
scontrol show partition hgpu2p
scontrol show partition hgpu4
printf 'NODE_CAPACITY\n'
sinfo -N -o '%N|%P|%T|%C|%m|%G'
printf 'FILESYSTEM\n'
df -h /data1/home/sunyiq
printf 'ISOLATED_CANDIDATE\n'
candidate='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922'
if [ -e "$candidate" ] || [ -L "$candidate" ]; then
    printf 'CANDIDATE_EXISTS %s\n' "$candidate"
    stat -c '%F|%U|%a|%n' "$candidate"
else
    printf 'CANDIDATE_ABSENT %s\n' "$candidate"
fi
printf 'EXISTING_RELEVANT_ROOTS_NAMES_ONLY\n'
find /data1/home/sunyiq -maxdepth 1 -type d -name 'kalmannet*tukf09*' -printf '%p\n'
printf 'CONDA_ENVIRONMENT_NAMES_ONLY\n'
if [ -d /data1/home/sunyiq/miniconda3/envs ]; then
    find /data1/home/sunyiq/miniconda3/envs -maxdepth 1 -mindepth 1 -type d -printf '%p\n'
fi
printf 'SHARED_PACKAGE_METADATA_NAMES_ONLY\n'
site='/data1/home/sunyiq/miniconda3/envs/nh_final/lib/python3.11/site-packages'
if [ -d "$site" ]; then
    find "$site" -maxdepth 1 -type d \( -name 'numpy-*.dist-info' -o -name 'torch-*.dist-info' -o -name 'psutil-*.dist-info' \) -printf '%f\n'
fi
printf 'SCHEDULER_MEMORY_ENFORCEMENT\n'
scontrol show config | awk '/ProctrackType|TaskPlugin|JobAcctGatherType|JobAcctGatherFrequency|SelectType|EnforcePartLimits|PriorityType|AccountingStorageEnforce/ {print}'
printf 'PREFLIGHT_READ_ONLY_COMPLETE\n'
