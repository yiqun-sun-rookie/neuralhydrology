#!/bin/bash
set -eo pipefail
phase='/data1/home/sunyiq/kalmannet_original_noise_multiday_20261007_attempt1'
if [ -e "$phase" ]; then
    printf 'PRIVATE_ROOT_ALREADY_EXISTS\n'
    exit 1
fi
printf 'PRIVATE_ROOT_ABSENT\n'
scontrol show partition hcpu48y
sinfo -p hcpu48y -o '%P %a %l %D %t %N'
squeue -u sunyiq -h -o '%i %j %t %C %M %R'
sacct -u sunyiq -S 2026-10-05 -X -n -P -o JobID,JobName,State,Partition,AllocCPUS,ReqTRES,AllocTRES | tail -15
test -x /data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B -c 'import sys,json,numpy,psutil; print(json.dumps({"python":sys.version,"numpy":numpy.__version__,"psutil":psutil.__version__}))'
