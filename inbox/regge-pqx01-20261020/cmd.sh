#!/bin/bash
set -eo pipefail
date -u
hostname
id
squeue -u sunyiq -o "%.18i %.24j %.10P %.10T %.12M %.40R"
sinfo -p hcpu48 -o "%.12P %.8a %.8D %.10t %.40N"
scontrol show partition hcpu48
df -h /data1/home/sunyiq
TASK_ROOT=/data1/home/sunyiq/regge_experiments/REGGE-PQX01-FROZEN-QE-CROSSBANK/20261020-v01
if [ -e "$TASK_ROOT" ]; then
    printf 'TARGET_EXISTS %s\n' "$TASK_ROOT"
    ls -ld "$TASK_ROOT"
else
    printf 'TARGET_ABSENT %s\n' "$TASK_ROOT"
fi
test -x /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
printf 'NH_FINAL_PYTHON_PRESENT\n'
type sbatch
