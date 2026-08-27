#!/bin/bash
set -eo pipefail

JOB_ID=215189
ROOT="/data1/home/sunyiq/zhenjiang_latent_da_20260827"
echo "MONITOR_START $(date -Is)"
echo "SQUEUE"
squeue -j "${JOB_ID}" -h -o '%i|%j|%T|%P|%M|%R' || true
echo "GPU_PARTITION_NODES"
sinfo -p hgpu2p,hgpu4,hgpu8 -N -h -o '%N|%P|%T|%G|%E' || true
echo "GPU_QUEUE_HEAD"
squeue -p hgpu2p,hgpu4,hgpu8 -h -o '%i|%u|%j|%T|%P|%M|%R' | head -40 || true
echo "PRIORITY"
sprio -j "${JOB_ID}" -l || true
echo "SACCT"
sacct -j "${JOB_ID}" -X -n -P \
  --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,AllocTRES || true
echo "SCONTROL"
scontrol show job "${JOB_ID}" | tr ' ' '\n' | \
  grep -E '^(JobId|JobName|JobState|Reason|RunTime|TimeLimit|NodeList|BatchHost|StdOut|StdErr)=' || true
echo "LOGS"
for log in "${ROOT}"/logs/zlda-smoke01-"${JOB_ID}".out "${ROOT}"/logs/zlda-smoke01-"${JOB_ID}".err
do
  if [ -f "${log}" ]; then
    echo "LOG_FILE ${log} bytes=$(stat -c '%s' "${log}") modified=$(stat -c '%y' "${log}")"
    tail -80 "${log}"
  else
    echo "LOG_MISSING ${log}"
  fi
done
echo "RESULT_FILES"
find "${ROOT}/run/results/runtime/zhenjiang_latent_gru_kalmannet_hpc_smoke_v1" \
  -maxdepth 4 -type f -printf '%P|%s\n' 2>/dev/null | sort || true
echo "MONITOR_END $(date -Is)"
