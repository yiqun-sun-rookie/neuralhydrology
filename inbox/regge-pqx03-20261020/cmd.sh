#!/bin/bash
set -eo pipefail
date -u
hostname
id -un
squeue -u sunyiq -o '%.18i %.28j %.10T %.12M %.40R'
sinfo -h -p hcpu48,hcpu48y,hgpu2p -o '%P|%a|%l|%D|%T|%C'
test -x /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
TASK_BASE=/data1/home/sunyiq/regge_experiments/REGGE-PQX03-FORECAST-OBJECTIVE-FACTORIAL
TASK_ROOT="$TASK_BASE/20261020-v01"
KEY_ROOT="$TASK_BASE/20261020-v01-transfer"
test ! -e "$TASK_ROOT"
umask 077
if [ -e "$KEY_ROOT" ]; then
    test -s "$KEY_ROOT/transfer_private.pem"
    test -s "$KEY_ROOT/transfer_public.pem"
else
    mkdir -p "$TASK_BASE"
    mkdir "$KEY_ROOT"
    openssl genrsa -out "$KEY_ROOT/transfer_private.pem" 2048
    openssl rsa -in "$KEY_ROOT/transfer_private.pem" -pubout -out "$KEY_ROOT/transfer_public.pem"
fi
printf 'PQX03_PUBLIC_KEY_BEGIN\n'
cat "$KEY_ROOT/transfer_public.pem"
printf 'PQX03_PUBLIC_KEY_END\n'
printf 'PQX03_ROOT_ABSENT_AND_ENV_PRESENT\n'
