#!/bin/bash
set -eo pipefail
test "$(id -un)" = sunyiq
printf 'RESOURCE_PROBE_UTC='
date -u '+%Y-%m-%dT%H:%M:%SZ'
parent=/data1/home/sunyiq
root=/data1/home/sunyiq/china_negative_repair_20261006_001
test "$(readlink -e "$parent")" = "$parent"
ls -ld -- "$parent"
if test -e "$root" || test -L "$root"; then
    printf 'ROOT_OCCUPIED=%s\n' "$root"
    exit 73
fi
printf 'ROOT_ABSENT=%s\n' "$root"
df -Pk "$parent"
printf 'OWN_EXISTING_JOBS_BEGIN\n'
timeout 15 squeue -u sunyiq -h -o '%.20i %.12P %.50j %.12T %.10M %.6D %.20R'
printf 'OWN_EXISTING_JOBS_END\n'
printf 'GPU_RESOURCE_BEGIN\n'
timeout 15 sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -N -O nodelist:16,partition:12,gres:24,gresused:32,cpusstate:18
printf 'GPU_RESOURCE_END\n'
printf 'READ_ONLY_RESOURCE_PROBE_COMPLETE\n'
