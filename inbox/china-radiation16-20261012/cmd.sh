#!/bin/bash
set -eo pipefail
test "$(id -un)" = sunyiq
printf 'OWN_RADIATION_RESOURCE_BEGIN\n'
date -u '+OWN_RADIATION_QUERY_UTC=%Y-%m-%dT%H:%M:%SZ'
task_root='/data1/home/sunyiq/china_radiation_16_hpc_20261012_001'
if test -e "$task_root"; then printf 'OWN_ROOT_EXISTS=1\n'; else printf 'OWN_ROOT_EXISTS=0\n'; fi
test -x /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
printf 'OWN_PYTHON_EXISTS=1\n'
if test -f /data1/home/sunyiq/.config/earthengine/credentials; then printf 'OWN_EE_CREDENTIAL_FILE_EXISTS=1\n'; else printf 'OWN_EE_CREDENTIAL_FILE_EXISTS=0\n'; fi
timeout 12s sinfo -p hgpu2p,hcpu48 -o '%P|%a|%l|%D|%N|%T'
timeout 12s squeue -u sunyiq -h -o '%i|%j|%T|%R'
timeout 12s scontrol show partition hgpu2p
printf 'OWN_RADIATION_RESOURCE_DONE\n'
