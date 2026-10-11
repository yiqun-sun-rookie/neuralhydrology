#!/bin/bash
set -eo pipefail
date -u '+RESOURCE_COLLECTION_UTC=%Y-%m-%dT%H:%M:%SZ'
task_target='/data1/home/sunyiq/us_nonnegative_repair_execution_20261010_001'
if [ -e "$task_target" ] || [ -L "$task_target" ]; then
  printf 'ISOLATED_TARGET_ALREADY_EXISTS=%s\n' "$task_target"
  exit 1
fi
printf 'ISOLATED_TARGET_ABSENT=%s\n' "$task_target"
test -d '/data1/home/sunyiq'
test -x '/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python'
printf 'EXISTING_PYTHON_PATH_PRESENT\n'
df -h /data1
squeue -u sunyiq -h -o '%i|%j|%T|%P|%D|%R'
sinfo -p hgpu2p -N -O nodelist,gres:14,gresused:24,cpusstate
printf 'READ_ONLY_RESOURCE_PROBE_DONE\n'
