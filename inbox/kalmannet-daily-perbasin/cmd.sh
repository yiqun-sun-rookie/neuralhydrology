#!/usr/bin/env bash
set -eo pipefail
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_state_update_control_20260921_v1"
echo "FIXED_CONTROL_RESOURCE_PROBE_V1"
echo "sequence=187"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host=$(hostname)"
echo "OWN_QUEUE_BEGIN"
squeue -u "$USER" -h -o '%i|%j|%T|%P|%R|%M|%l'
echo "OWN_QUEUE_END"
echo "CPU_PARTITION_BEGIN"
sinfo -h -p hcpu48 -o '%P|%a|%D|%t|%C'
scontrol show partition hcpu48 | grep -E 'PartitionName=|OverSubscribe=|State=|TotalCPUs='
echo "CPU_PARTITION_END"
if [[ -e "$OUTPUT_ROOT" ]]; then
  echo "PROPOSED_ROOT_ABSENT=no"
else
  echo "PROPOSED_ROOT_ABSENT=yes"
fi
echo "RESOURCE_PROBE_COMPLETE"
