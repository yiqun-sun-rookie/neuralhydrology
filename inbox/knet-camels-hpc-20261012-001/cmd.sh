#!/bin/bash
set -eo pipefail
TASK_ROOT=/data1/home/sunyiq/knet_camels_hpc_20261012_001
printf 'TIME_UTC='; date -u +%FT%TZ
printf 'NODE='; hostname
printf 'USER='; id -un
printf 'STORAGE
'; df -h /data1/home/sunyiq
printf 'OWN_JOBS
'; squeue -u sunyiq -h -o '%i|%j|%T|%P|%C|%R'
printf 'PARTITIONS
'; sinfo -p hgpu2p,hgpu4,hgpu8,hcpu48 -o '%P|%a|%l|%D|%t|%C'
printf 'CPU_RESOURCES
'; sinfo -p hgpu2p,hgpu4,hgpu8 -N -o '%N|%P|%T|%C|%G'
for p in /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; do
 if [ -f "$p" ]; then printf 'ENV_PATH_PRESENT=%s
' "$p"; else printf 'ENV_PATH_MISSING=%s
' "$p"; fi
done
if [ -e "$TASK_ROOT" ]; then printf 'EXCLUSIVE_ROOT_ALREADY_EXISTS=%s
' "$TASK_ROOT"; exit 1; fi
mkdir "$TASK_ROOT"
mkdir "$TASK_ROOT/logs" "$TASK_ROOT/receipts" "$TASK_ROOT/attempts"
printf '%s
' 'knet-camels-hpc-20261012-001; isolated preparation; existing jobs and environments read-only' > "$TASK_ROOT/OWNER.txt"
printf 'EXCLUSIVE_ROOT_CREATED=%s
' "$TASK_ROOT"
