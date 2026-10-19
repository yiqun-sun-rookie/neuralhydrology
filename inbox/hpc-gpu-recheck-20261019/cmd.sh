#!/bin/bash
set -u
query() { printf '\nQUERY=%s\n' "$*"; timeout 30 "$@"; printf 'QUERY_EXIT=%s\n' "$?"; }
query date -Iseconds
query sinfo -N -n ngu001,ngu002,ngu101,ngu103,ngu201,ngu202,ngu203 -O 'partition:12,nodelist:16,gres:18,gresused:30,cpusstate:24'
query sinfo -N -n ngu001,ngu002,ngu101,ngu103,ngu201,ngu202,ngu203 -o '%N|%P|%t|%G|%C|%E'
for node in ngu001 ngu002 ngu101 ngu103 ngu201 ngu202 ngu203; do query scontrol -o show node "$node"; done
query squeue -h -u sunyiq -o '%i|%j|%T|%N' --name=ghr_001_261019,ghr_002_261019,ghr_101_261019,ghr_103_261019,ghr_201_261019,ghr_202_261019,ghr_203_261019
if test -e /data1/home/sunyiq/hpc_gpu_recheck_20261019_001; then echo AUDIT_ROOT_ALREADY_EXISTS; else echo AUDIT_ROOT_UNUSED; fi
echo METADATA_ONLY_NO_SUBMISSIONS_NO_NODE_CHANGES
exit 0
