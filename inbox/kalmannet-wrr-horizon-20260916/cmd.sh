#!/bin/bash
set -eo pipefail
printf 'READ_ONLY_48GB_RESOURCE_CHECK_AND_JOB_226070_STATUS\n'
date -Is
printf '\n48GB_PARTITION_DETAILS\n'
scontrol show partition hgpu4
sinfo -p hgpu4,hgpu8 -N -o '%N %P %t %G %C'
for node in ngu101 ngu102 ngu103 ngu104 ngu201 ngu202 ngu203; do
  printf '\nNODE_DETAILS %s\n' "$node"
  scontrol show node "$node"
done
printf '\nUSER_JOBS_READ_ONLY\n'
squeue -u sunyiq -o '%.18i %.16P %.42j %.10T %.12M %.12l %.6D %R'
root=/data1/home/sunyiq/kalmannet_wrr_training_horizon_20260916
repo="$root/repo"
squeue -j 226070 -o '%.18i %.16P %.42j %.10T %.12M %.12l %.6D %R' || true
sacct -j 226070 --format=JobID,JobName,State,ExitCode,Elapsed,NodeList,AllocTRES,MaxRSS -P
printf '\nSCHEDULER_START_ESTIMATE\n'
squeue --start -j 226070 || true
scontrol show job 226070 || true
printf '\nREQUESTED_PARTITION_STATUS\n'
sinfo -p hgpu8 -N -o '%N %t %G %C'
show_file() {
  printf '\nFILE %s\n' "$1"
  if [ -f "$1" ]; then cat "$1"; else printf 'NOT_PRESENT\n'; fi
}
show_file "$root/environment_metadata_before_submission.json"
show_file "$repo/artifacts/hpc_execution/status.json"
show_file "$repo/artifacts/resource_probes/20260916_horizon25_seed42_attempt001/monitor_result.json"
show_file "$repo/artifacts/resource_probes/20260916_horizon25_seed42_attempt001/worker_result.json"
show_file "$repo/artifacts/training_horizon_common_origins_v2/seed42/status.json"
show_file "$repo/artifacts/training_horizon_common_origins_v2/seed42/output12/status.json"
show_file "$repo/artifacts/training_horizon_common_origins_v2/seed42/output25/status.json"
if [ -f "$repo/artifacts/hpc_execution/optimizer_steps.jsonl" ]; then
  printf '\nOPTIMIZER_RECEIPTS_FIRST_AND_LAST\n'
  head -n 1 "$repo/artifacts/hpc_execution/optimizer_steps.jsonl"
  tail -n 2 "$repo/artifacts/hpc_execution/optimizer_steps.jsonl"
fi
for file in "$root/logs/job_226070.out" "$root/logs/job_226070.err" "$repo/artifacts/resource_probes/20260916_horizon25_seed42_attempt001/worker.stderr.log"; do
  printf '\nTAIL %s\n' "$file"
  if [ -f "$file" ]; then tail -n 55 "$file"; else printf 'NOT_PRESENT\n'; fi
done
printf '\nREAD_ONLY_STATUS_COMPLETE\n'
