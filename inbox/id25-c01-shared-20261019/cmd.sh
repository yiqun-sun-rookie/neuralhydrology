#!/bin/bash
set -u
query() { printf '\nQUERY=%s\n' "$*"; timeout 35 "$@"; printf 'QUERY_EXIT=%s\n' "$?"; }
query date -Iseconds
query scontrol -o show job 245242
query squeue -j 245242 --start -o '%i|%P|%T|%r|%S|%R'
query sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -N -O 'partition:12,nodelist:16,gres:18,gresused:30,cpusstate:24'
query sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -N -o '%P|%N|%t|%G|%C'
query sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -R
for partition in hgpu2p hgpu2 hgpu4 hgpu8; do query scontrol -o show partition "$partition"; done
query sacctmgr -n -P show assoc user=sunyiq account=g_sunyiq format=Cluster,Account,User,Partition,QOS
echo READ_ONLY_RESOURCE_QUERY_NO_SUBMISSION_NO_JOB_UPDATE
exit 0
