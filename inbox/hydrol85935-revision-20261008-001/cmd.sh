#!/bin/bash
# OPS (standing authorization): move OWN pending export job 241344 from the GPU queue to an idle CPU partition.
# The export only reads records/hashes and writes the packet (no GPU use); script, code and science unchanged.
J=241344
echo "MV_TIME $(date -u +%FT%TZ)"
scontrol show job $J | grep -oE "(JobName|JobState|Reason|Partition|TresPerNode|Gres|ExcNodeList|NumCPUs|Command|Dependency|TimeLimit)=[^ ]*"
[ "$(squeue -j $J -h -o %T)" = PENDING ] || { echo MV_NOT_PENDING_NO_CHANGE; exit 3; }
[ "$(squeue -j $J -h -o %j)" = hydrol85935-v010-export ] || { echo MV_WRONG_JOB_NO_CHANGE; exit 3; }
sinfo -p hcpu48,hcpu48y -h -o "%P %a %D %T" 2>&1
P=$(for p in hcpu48 hcpu48y; do n=$(sinfo -p $p -h -t idle -o "%D" | awk '{s+=$1} END{print s+0}'); echo "$n $p"; done | sort -nr | awk '$1>0{print $2; exit}')
[ -n "$P" ] || { echo MV_NO_IDLE_CPU_PARTITION_NO_CHANGE; exit 3; }
echo "MV_TARGET $P"
for spec in "TresPerNode=" "Gres=" "Gres=none" "TresPerNode=none"; do
  out=$(scontrol update JobId=$J Partition=$P $spec 2>&1); echo "MV_TRY $spec rc=$? $out"
  [ "$(squeue -j $J -h -o %P)" = "$P" ] && break
done
sleep 20
echo MV_AFTER; scontrol show job $J | grep -oE "(JobState|Reason|Partition|TresPerNode|Gres|NodeList|StartTime)=[^ ]*"
squeue -j $J -h -o "%i|%T|%r|%P|%b|%S|%N"
[ "$(squeue -j $J -h -o %P)" = "$P" ] && echo MV_DONE || echo MV_UNCHANGED
exit 0
