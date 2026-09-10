#!/bin/bash
# channel=kalmannet-daily-perbasin sequence=93 purpose=read-only-all-gpu-live-and-start-estimates
set -u
set -o pipefail
printf '%s\n' 'ALL_GPU_NODES_BEGIN'
timeout 20s sinfo -a -N -h -o '%N|%P|%G|%b|%C|%T' | awk -F'|' '$3 ~ /gpu/'
printf 'ALL_GPU_NODES_EXIT=%s\n' "$?"
printf '%s\n' 'RUNNING_GPU_JOBS_BEGIN'
timeout 20s squeue -r -h -p hgpu2p,hgpu2,hgpu4,hgpu8 -t RUNNING -o '%i|%u|%j|%P|%M|%l|%b|%N|%e'
printf 'RUNNING_GPU_JOBS_EXIT=%s\n' "$?"
printf '%s\n' 'TARGET_JOB_BEGIN'
timeout 20s scontrol show job -dd 224875
printf 'TARGET_JOB_EXIT=%s\n' "$?"
printf '%s\n' 'TARGET_START_ESTIMATE_BEGIN'
timeout 20s squeue --start -j 224875 -o '%i|%j|%T|%P|%S|%Y|%R'
printf 'TARGET_START_ESTIMATE_EXIT=%s\n' "$?"
printf '%s\n' 'OWN_GPU_QUEUE_BEGIN'
timeout 20s squeue -r -u sunyiq -h -o '%i|%j|%T|%P|%D|%C|%b|%Z|%R'
printf 'OWN_GPU_QUEUE_EXIT=%s\n' "$?"
printf '%s\n' 'READ_ONLY_GPU_START_QUERY_COMPLETE submissions=0 cancellations=0 updates=0'
